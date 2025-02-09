# [Input Data](@id inputdataContinuous)

The FactorGraph package requires knowledge about the joint probability density function ``g(\mathcal{X})`` of the set of random variables ``\mathcal{X} = \{x_1,\dots,x_n\}`` that can be factorised proportionally  (``\propto``) to a product of local functions:
```math
    g(\mathcal{X}) \propto \prod_{i=1}^m \psi_i(\mathcal{X}_i).
```
The FactorGraph package supports continuous random variables, where local function ``\psi_i(\mathcal{X}_i)`` is defined as a continuous Gaussian distribution:
```math
  \mathcal{N}(z_i|\mathcal{X}_i,v_i) \propto \exp\Bigg\{-\cfrac{[z_i-h_i(\mathcal{X}_i)]^2}{2v_i}\Bigg\}.
```
Hence, the local function is associated with mean ``z_i``, variance  ``v_i``, and linear equation ``h_i(\mathcal{X}_i)``. To describe the joint probability density function ``g(\mathcal{X})``, it is enough to define the Jacobian matrix containing coefficients of the equations, and vectors of mean and variance values. Then, the ``i``-th row of the Jacobian matrix, with consistent entries of mean and variance, defines the local function ``\psi_i(\mathcal{X}_i)``.

The input data used to describe the joint probability density function can be given using HDF5 and XLSX input files or by passing data directly via command-line arguments. The examples of the input files are located in the `src/example`. Note that, with large-scale systems, we strongly recommend using the HDF5 file data format.

Thus, the input data structure includes the `jacobian` variable, while variables `observation` and `variance` represent mean and variance vectors, respectively. The functions `continuousModel()` and `continuousTreeModel()` accept HDF5 and XLSX input files with fields/sheets `jacobian`, `observation` and `variance`. Also, these functions accept variables `jacobian`, `observation` and `variance` directly via function arguments.

---


#### Build the graphical model by passing arguments
Let us observe the following joint probability density function:
```math
    g(\mathcal{X}) \propto  \exp\Bigg\{-\cfrac{[2.5 - 0.2x_1]^2}{2\cdot 1.1}\Bigg\}\exp\Bigg\{-\cfrac{[0.6 - (2.1x_1 + 3.4x_2)]^2}{2\cdot 3.5}\Bigg\}
```

We can describe the joint probability density function using variables `jacobian`, `observation` and `variance`. Passing data directly via command-line support the following format, where the Jacobian matrix can be defined as a full or sparse matrix:
```julia-repl
jacobian = zeros(2, 2)
jacobian[1, 1] = 0.2; jacobian[2, 1] = 2.1; jacobian[2, 2] = 3.4
observation = [2.5; 0.6]
variance = [1.1; 3.5]

gbp = continuousModel(jacobian, observation, variance)
```
Here, the variable `gbp` holds the main composite type related to the continuous model. In the case of a tree factor graph, when you want to use a forward-backward algorithm, then the following command can be used:
```julia-repl
gbp = continuousTreeModel(jacobian, observation, variance)
```

---

#### Build the graphical model using HDF5 or XLSX files
Further, we can represet the `jacobian` variable using row and column indecies:
```julia-repl
jacobian = zeros(3, 3)
jacobian[1, 1] = 1; jacobian[1, 2] = 1; jacobian[1, 3] = 0.2
jacobian[2, 1] = 2; jacobian[2, 2] = 1; jacobian[2, 3] = 2.1
jacobian[3, 1] = 2; jacobian[3, 2] = 2; jacobian[3, 3] = 3.4
```
The Jacobian matrix stored in the HDF5 or XLSX input file requires format with row and column indices with the corresponding coefficient. The input file must contain three fields with the HDF5, or three sheets with the XLSX file, with names `jacobian`, `observation` and `variance`.