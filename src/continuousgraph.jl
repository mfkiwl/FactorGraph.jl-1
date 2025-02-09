mutable struct ContinuousSystem
    jacobian::SparseMatrixCSC{Float64,Int64}
    jacobianTranspose::SparseMatrixCSC{Float64,Int64}
    observation::Array{Float64,1}
    variance::Array{Float64,1}
    data::String
end

mutable struct ContinuousGraph
    Nvariable::Int64
    Nfactor::Int64
    Nindirect::Int64
    Nlink::Int64
    virtualMean::Float64
    virtualVariance::Float64
    meanDirect::Array{Float64,1}
    weightDirect::Array{Float64,1}
    meanIndirect::Array{Float64,1}
    varianceIndirect::Array{Float64,1}
    coefficient::Array{Float64,1}
    toVariable::SparseMatrixCSC{Int64, Int64}
    toFactor::SparseMatrixCSC{Int64, Int64}
    rowptr::Vector{Vector{Int64}}
    colptr::Vector{Vector{Int64}}
    colptrMarginal::Vector{Vector{Int64}}
    alphaNew::Array{Float64,1}
    alphaOld::Array{Float64,1}
    iterateFactor::Array{Int64,1}
    iterateVariable::Array{Int64,1}
    iterateMarginal::Array{Int64,1}
    dynamic::Array{Int64,1}
end

mutable struct ContinuousTreeGraph
    Nvariable::Int64
    Nfactor::Int64
    Nlink::Int64
    root::Int64
    virtualMean::Float64
    virtualVariance::Float64
    meanDirect::Array{Float64,1}
    weightDirect::Array{Float64,1}
    rowForward::Vector{Vector{Int64}}
    rowBackward::Vector{Vector{Int64}}
    colForward::Vector{Vector{Int64}}
    colBackward::Vector{Vector{Int64}}
    incomingToFactor::Vector{Vector{Int64}}
    incomingToVariable::Vector{Vector{Int64}}
    iterateFactor::Array{Int64,1}
    iterateVariable::Array{Int64,1}
    passFactorVariable::Int64
    passVariableFactor::Int64
    forward::Bool
    backward::Bool
end

mutable struct ContinuousInference
    fromFactor::Array{Int64,1}
    toVariable::Array{Int64,1}
    meanFactorVariable::Array{Float64,1}
    varianceFactorVariable::Array{Float64,1}
    fromVariable::Array{Int64,1}
    toFactor::Array{Int64,1}
    meanVariableFactor::Array{Float64,1}
    varianceVariableFactor::Array{Float64,1}
    mean::Array{Float64,1}
    variance::Array{Float64,1}
end

struct ContinuousModel
    graph::ContinuousGraph
    inference::ContinuousInference
    system::ContinuousSystem
end

struct ContinuousTreeModel
    graph::ContinuousTreeGraph
    inference::ContinuousInference
    system::ContinuousSystem
end

########## Form a graph with continuous variables and initialize messages ##########
function continuousModel(
    args...;
    prob::Float64 = 0.6,
    alpha::Float64 = 0.4,
    mean::Float64 = 0.0,
    variance::Float64 = 1e10)

    checkKeywords(prob, alpha, variance)
    if checkFileOrArguments(args)
        system = readContinuousFile(args)
    else
        system = readContinuousArguments(args)
    end

    graph, inference = makeContinuousGraph(system, mean, variance, prob, alpha)

    return ContinuousModel(graph, inference, system)
end

########## Form a tree factor graph and initialize messages ##########
function continuousTreeModel(
    args...;
    mean::Float64 = 0.0,
    variance::Float64 = 1e10,
    root::Int64 = 1)

    if checkFileOrArguments(args)
        system = readContinuousFile(args)
    else
        system = readContinuousArguments(args)
    end

    graph, inference = makeContinuousTreeGraph(system, mean, variance, root)

    return ContinuousTreeModel(graph, inference, system)
end

########## Load from HDF5 or XLSX files ##########
function readContinuousFile(args)
    fullpath, extension, dataname = checkImportFile(args)

    #### Read from HDF5 or XLSX file
    if extension == ".h5"
        list = h5read(fullpath, "/jacobian")::Array{Float64,2}
        jacobian = sparse(list[:,1], list[:,2], list[:,3])::SparseMatrixCSC{Float64,Int64}
        jacobianTranspose = sparse(list[:,2], list[:,1], list[:,3])::SparseMatrixCSC{Float64,Int64}

        observation = h5read(fullpath, "/observation")::Array{Float64,1}
        variance = h5read(fullpath, "/variance")::Array{Float64,1}
    elseif extension == ".xlsx"
        xf = XLSX.openxlsx(fullpath, mode = "r")
        if "jacobian" in XLSX.sheetnames(xf)
            start = startxlsx(xf["jacobian"])
            list = xf["jacobian"][:][start:end, :]
            jacobian = sparse(list[:, 1], list[:, 2], list[:, 3])
            jacobianTranspose = sparse(list[:, 2], list[:, 1], list[:, 3])
        else
            throw(ErrorException("error opening sheet jacobian"))
        end
        if "observation" in XLSX.sheetnames(xf)
            start = startxlsx(xf["observation"])
            observation = xf["observation"][:][start:end]
        else
            throw(ErrorException("error opening sheet observation"))
        end
        if "variance" in XLSX.sheetnames(xf)
            start = startxlsx(xf["variance"])
            variance = xf["variance"][:][start:end]
        else
            throw(ErrorException("error opening sheet variance"))
        end
    else
        error("the input data is not a valid format")
    end

    return ContinuousSystem(jacobian, jacobianTranspose, observation, variance, dataname)
end

########## Read in-Julia system model ##########
function readContinuousArguments(args)
    if typeof(args[1]) == Array{Float64, 2}
        jacobian = sparse(args[1])
    else
        jacobian = args[1]
    end

    jacobianTranspose = copy(transpose(jacobian))
    observation = args[2]
    variance = args[3]

    return ContinuousSystem(jacobian, jacobianTranspose, observation, variance, "noname")
end

########## Produce the graphical model ##########
function makeContinuousGraph(system, meanVirtual, varianceVirtual, dampProbability, dampAlpha)
    ### Number of factor and variable nodes
    Nfactor, Nvariable = size(system.jacobian)

    ### Find graph numbers, set the direct mean and variance and internal factor numeration
    Ndirect = 0; Nlink = 0; Nindirect = 0
    meanDirect = fill(meanVirtual / varianceVirtual, Nvariable)
    weightDirect = fill(1 / varianceVirtual, Nvariable)
    dynamic = fill(0, Nfactor)

    @inbounds for i = 1:Nfactor
        NvariableInRow = system.jacobianTranspose.colptr[i + 1] - system.jacobianTranspose.colptr[i]
        if NvariableInRow == 1
            Ndirect += NvariableInRow
            variable = system.jacobianTranspose.rowval[system.jacobianTranspose.colptr[i]]
            meanDirect[variable] = 0.0
            weightDirect[variable] = 0.0
        else
            Nlink += NvariableInRow
            Nindirect += 1
            dynamic[i] = Nindirect
        end
    end

    ### Pass through the columns
    colptr = [Int[] for i = 1:Nvariable]
    colptrMarginal = [Int[] for i = 1:Nvariable]
    toVariable = fill(0, Nlink)
    fromFactor = similar(toVariable)
    idxi = 1
    @inbounds for col = 1:Nvariable
        for i = system.jacobian.colptr[col]:(system.jacobian.colptr[col + 1] - 1)
            row = system.jacobian.rowval[i]
            NvariableInRow = system.jacobianTranspose.colptr[row + 1] - system.jacobianTranspose.colptr[row]
            if NvariableInRow == 1
                meanDirect[col] += system.observation[row] * system.jacobian[row, col] / system.variance[row]
                weightDirect[col] += system.jacobian[row, col]^2 / system.variance[row]
            else
                push!(colptr[col], idxi)
                push!(colptrMarginal[col], idxi)
                toVariable[idxi] = col
                fromFactor[idxi] = row
                idxi += 1
            end
        end
    end

    ### Pass through the rows and send messages from singly-connected factor nodes to all indirect links
    coefficient = fill(0.0, Nlink)
    meanIndirect = similar(coefficient)
    varianceIndirect = similar(coefficient)
    meanFactorVariable = similar(coefficient)
    varianceFactorVariable = similar(coefficient)
    meanVariableFactor = similar(coefficient)
    varianceVariableFactor = similar(coefficient)

    fromVariable = fill(0, Nlink)
    toFactor = similar(fromVariable)
    rowptr = [Int[] for i = 1:Nindirect]
    idxi = 1
    @inbounds for (col, val) in enumerate(dynamic)
        if val != 0
            for i = system.jacobianTranspose.colptr[col]:(system.jacobianTranspose.colptr[col + 1] - 1)
                row = system.jacobianTranspose.rowval[i]

                coefficient[idxi] = system.jacobianTranspose[row, col]
                meanIndirect[idxi] = system.observation[col]
                varianceIndirect[idxi] = system.variance[col]

                toFactor[idxi] = col
                fromVariable[idxi] = row
                push!(rowptr[dynamic[col]], idxi)

                varianceVariableFactor[idxi] = 1 / weightDirect[row]
                meanVariableFactor[idxi] = meanDirect[row] * varianceVariableFactor[idxi]
                idxi += 1
            end
        end
    end

    ### Message send indices
    links = collect(1:idxi - 1)
    sendToFactor = sparse(toFactor, fromVariable, links, Nfactor, Nvariable)
    sendToVariable = sparse(toVariable, fromFactor, links, Nvariable, Nfactor)

    ### Set damping parameters
    alphaNew = fill(1.0, Nlink)
    alphaOld = fill(0.0, Nlink)
    bernoulliSample = randsubseq(collect(1:Nlink), dampProbability)
    @inbounds for i in bernoulliSample
        alphaNew[i] = 1.0 - dampAlpha
        alphaOld[i] = dampAlpha
    end

    ### Initialize marginal mean and variance vectors
    mean = fill(0.0, Nvariable)
    variance = fill(0.0, Nvariable)

    ### Iteration counters
    iterateFactor = collect(1:Nindirect)
    iterateVariable = collect(1:Nvariable)
    iterateMarginal = copy(iterateVariable)

    return ContinuousGraph(Nvariable, Nfactor, Nindirect, Nlink,
            meanVirtual, varianceVirtual, meanDirect, weightDirect, meanIndirect, varianceIndirect, coefficient,
            sendToVariable, sendToFactor, rowptr, colptr, colptrMarginal, alphaNew, alphaOld,
            iterateFactor, iterateVariable, iterateMarginal, dynamic),
           ContinuousInference(fromFactor, toVariable, meanFactorVariable, varianceFactorVariable,
            fromVariable, toFactor, meanVariableFactor, varianceVariableFactor, mean, variance)
end

########## Produce the graphical model ##########
function makeContinuousTreeGraph(system, virtualMean, virtualVariance, root)
    ### Number of factor and variable nodes
    Nfactor, Nvariable = size(system.jacobian)

    ### Find graph numbers, set the direct mean and variance, set factor numeration and pass through the rows
    Nlink = 0; Nindirect = 0
    meanDirect = fill(virtualMean / virtualVariance, Nvariable)
    weightDirect = fill(1 / virtualVariance, Nvariable)

    rowForward = [Int[] for i = 1:Nfactor]; rowBackward = [Int[] for i = 1:Nfactor]
    incomingToVariable = [Int[] for i = 1:Nvariable]
    @inbounds for i = 1:Nfactor
        NvariableInRow = system.jacobianTranspose.colptr[i + 1] - system.jacobianTranspose.colptr[i]
        if NvariableInRow == 1
            variable = system.jacobianTranspose.rowval[system.jacobianTranspose.colptr[i]]
            meanDirect[variable] = 0.0
            weightDirect[variable] = 0.0
        else
            Nlink += NvariableInRow
            Nindirect += 1
            for j = system.jacobianTranspose.colptr[i]:(system.jacobianTranspose.colptr[i + 1] - 1)
                row = system.jacobianTranspose.rowval[j]
                push!(rowForward[i], row)
                push!(rowBackward[i], row)
            end
        end
    end

    ## Pass through the columns
    iterateVariable = fill(0, Nvariable)
    counter = 0
    colForward = [Int[] for i = 1:Nvariable]; colBackward = [Int[] for i = 1:Nvariable]
    incomingToFactor = [Int[] for i = 1:Nfactor]
    @inbounds for col = 1:Nvariable
        for i = system.jacobian.colptr[col]:(system.jacobian.colptr[col + 1] - 1)
            row = system.jacobian.rowval[i]
            NvariableInRow = system.jacobianTranspose.colptr[row + 1] - system.jacobianTranspose.colptr[row]
            if NvariableInRow == 1
                meanDirect[col] += system.observation[row] * system.jacobian[row, col] / system.variance[row]
                weightDirect[col] += system.jacobian[row, col]^2 / system.variance[row]
            else
                push!(colForward[col], row)
                push!(colBackward[col], row)
            end
        end
        if length(colForward[col]) == 1 && col != root
            counter += 1
            iterateVariable[counter] = col
        end
    end
    resize!(iterateVariable, counter)

    ### Initialize data
    fromVariable = fill(0, Nlink)
    toFactor = fill(0, Nlink)
    meanVariableFactor = fill(0.0, Nlink)
    varianceVariableFactor = fill(0.0, Nlink)

    fromFactor = fill(0, Nlink)
    toVariable = fill(0, Nlink)
    meanFactorVariable = fill(0.0, Nlink)
    varianceFactorVariable = fill(0.0, Nlink)

    mean = fill(0, Nvariable)
    variance = fill(0, Nvariable)

    passFactorVariable = 0
    passVariableFactor = 0
    iterateFactor = Int64[]

    return ContinuousTreeGraph(Nvariable, Nfactor, Nlink, root, virtualMean, virtualVariance, meanDirect, weightDirect,
            rowForward, rowBackward, colForward, colBackward, incomingToFactor, incomingToVariable,
            iterateFactor, iterateVariable, passFactorVariable, passVariableFactor, true, true),
           ContinuousInference(fromFactor, toVariable, meanFactorVariable, varianceFactorVariable,
            fromVariable, toFactor, meanVariableFactor, varianceVariableFactor, mean, variance)
end

