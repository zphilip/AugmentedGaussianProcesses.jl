

#### Optimization of the hyperparameters #### #TODO
function updateHyperParameters!(model::LinearModel,iter::Integer)
    grad_γ = 0.5*((trace(model.ζ)+norm(model.μ))/(model.γ^2.0)-model.nFeatures/model.γ);
    if model.VerboseLevel > 2
        println("Grad γ : $(grad_γ)")
    end
    model.γ += GradDescent.update(model.optimizers[1],grad_γ)
    model.HyperParametersUpdated = true
end

function updateHyperParameters!(model::NonLinearModel,iter::Integer)
    gradients = computeHyperParametersGradients(model,iter)
    if model.VerboseLevel > 1
        print("Hyperparameters  (param,coeff) $((getfield.(model.Kernels,:param),getfield.(model.Kernels,:coeff))) with gradients $(gradients[1:2]) \n")
    end
    applyHyperParametersGradients!(model,gradients)
    model.HyperParametersUpdated = true;
end


# Apply the gradients of the hyperparameters following Nesterov Accelerated Gradient Method and clipping method
function applyHyperParametersGradients!(model::GPModel,gradients)
    #Gradients contain the : kernel param gradients, kernel coeffs gradients and eventually the inducing points gradients
    for i in 1:model.nKernels
        model.Kernels[i].param += GradDescent.update(model.optimizers[i],gradients[1][i])
        model.Kernels[i].coeff += GradDescent.update(model.optimizers[i+model.nKernels],gradients[2][i])
        #Put a limit on the kernel coefficient value
        model.Kernels[i].coeff = model.Kernels[i].coeff > 0 ? model.Kernels[i].coeff : 0;
    end
    #Avoid the case where the coeff of a kernel overshoot to 0
    if model.nKernels == 1 && model.Kernels[1].coeff < 1e-14
        model.Kernels[1].coeff = 1e-12
    end
    if length(gradients)==3
         model.inducingPoints += GradDescent.update(model.optimizers[2*model.nKernels+1],gradients[3])
    end
end

#Compute a the derivative of the covariance matrix
function computeJ(model::FullBatchModel,derivative::Function)
    return CreateKernelMatrix(model.X,derivative)
end

function computeJ(model::SparseModel,derivative::Function)
    Jnm = CreateKernelMatrix(model.X[model.MBIndices,:],derivative,X2=model.inducingPoints)
    Jnn = CreateDiagonalKernelMatrix(model.X[model.MBIndices,:],derivative)
    Jmm = CreateKernelMatrix(model.inducingPoints,derivative)
    return Jnm,Jnn,Jmm
end

function CreateColumnRowMatrix(n,iter,gradient)
    K = zeros(n,n)
    K[iter,:] = gradient; K[:,iter] = gradient;
    return K
end

function CreateColumnMatrix(n,m,iter,gradient)
    K = zeros(n,m)
    K[:,iter] = gradient;
    return K
end

#Compute the gradients given the inducing point locations
function computeIndPointsJ(model::SparseModel,iter)
    dim = size(model.X,2)
    Dnm = zeros(model.nSamplesUsed,dim)
    Dmm = zeros(model.m,dim)
    Jnm = zeros(dim,model.nSamplesUsed,model.m)
    Jmm = zeros(dim,model.m,model.m)
    function derivative(X1,X2)
        tot = 0
        for i in 1:model.nKernels
            tot += model.Kernels[i].coeff*model.Kernels[i].compute_point_deriv(X1,X2)
        end
        return tot
    end
    #Compute the gradients given every other point
    for i in 1:model.nSamplesUsed
        Dnm[i,:] = derivative(model.X[model.MBIndices[i],:],model.inducingPoints[iter,:])
    end
    for i in 1:model.m
        Dmm[i,:] = derivative(model.inducingPoints[iter,:],model.inducingPoints[i,:])
    end
    for i in 1:dim
        Jnm[i,:,:] = CreateColumnMatrix(model.nSamplesUsed,model.m,iter,Dnm[:,i])
        Jmm[i,:,:] = CreateColumnRowMatrix(model.m,iter,Dmm[:,i])
    end
    return Jnm,Jmm
end

function computeHyperParametersGradients(model::FullBatchModel,iter::Integer)
    A = model.invK*(model.ζ+model.µ*transpose(model.μ))-eye(model.nSamples)
    #Update of both the coefficients and hyperparameters of the kernels
    gradients_kernel_param = zeros(model.nKernels)
    gradients_kernel_coeff = zeros(model.nKernels)
    for i in 1:model.nKernels
        V_param = model.invK*model.Kernels[i].coeff*computeJ(model,model.Kernels[i].compute_deriv)
        V_coeff = model.invK*computeJ(model,model.Kernels[i].compute)
        gradients_kernel_param[i] = 0.5*sum(V_param.*transpose(A))
        gradients_kernel_coeff[i] = 0.5*sum(V_coeff.*transpose(A))
    end

    return gradients_kernel_param,gradients_kernel_coeff
end



#Printing Functions

function printautotuninginformations(model::LinearModel)
#Print the updated values of the noise
    println("Gamma : $(model.γ)")
end

function printautotuninginformations(model::NonLinearModel)
#Print the updated values of the kernel hyperparameters
    for i in 1:model.nKernels
        print("Hyperparameters  (param,coeff) $((getfield.(model.Kernels,:param),getfield.(model.Kernels,:coeff))) with gradients $(gradients[1:2]) \n");
    end
end
