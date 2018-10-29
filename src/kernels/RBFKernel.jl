
"""
    Gaussian (RBF) Kernel
"""
struct RBFKernel{T<:AbstractFloat,KT<:KernelType} <: Kernel{T,KT}
    fields::KernelFields{T,KT}
    function RBFKernel{T,KT}(θ::Vector{T};variance::T=one(T),dim::Integer=0) where {T<:AbstractFloat,KT<:KernelType}
        if KT == ARDKernel
            if length(θ)==1 && dim ==0
                error("You defined an ARD RBF kernel without precising the number of dimensions or giving a vector for the lengthscale                   Please set dim in your kernel initialization")
            elseif dim!=0 && (length(θ)!=dim && length(θ)!=1)
                @warn "You did not use the same dimension for your params and dim, using the first value of params for all dimensions"
                θ = ones(dim,T=T)*θ[1]
            elseif length(θ)==1 && dim!=0
                θ = ones(dim)*θ[1]
            end
            dim = length(θ)
            return new{T,ARDKernel}(KernelFields{T,ARDKernel}(
                                        "Radial Basis",
                                        HyperParameter{T}(variance,interval(OpenBound(zero(T)),nothing),fixed=false),
                                        HyperParameters{T}(θ,[interval(OpenBound(zero(T)),NullBound{T}()) for _ in 1:dim]),dim,
                                        WeightedSqEuclidean(one(T)./(θ.^2))))
        else
            return new{T,IsoKernel}(KernelFields{T,IsoKernel}(
                                        "RBF",
                                        HyperParameter{T}(variance,interval(OpenBound(zero(T)),nothing),fixed=false),
                                        HyperParameters{T}(θ,[interval(OpenBound(zero(T)),NullBound{T}())]),1,
                                        SqEuclidean()))
        end
    end
end

function RBFKernel(θ::T1=1.0;variance::T2=one(T1),dim::Integer=0,ARD::Bool=false) where {T1<:Real,T2<:Real}
    if ARD
        RBFKernel{floattype(T1,T2),ARDKernel}([θ],variance=variance,dim=dim)
    else
        RBFKernel{floattype(T1,T2),IsoKernel}([θ],variance=variance)
    end
 end

function RBFKernel(θ::Array{T1,1};variance::T2=one(T1),dim::Integer=0) where {T1<:Real,T2<:Real}
    RBFKernel{floattype(T1,T2),ARDKernel}(θ,variance=variance,dim=dim)
end


@inline rbfkernel(z::T, l::T) where {T<:Real} = exp(-0.5*z/(l^2))

@inline rbfkernel(z::Real) = exp(-0.5*z)

function kappa(k::RBFKernel{T,IsoKernel}) where {T<:Real,KT}
    return z->rbfkernel(z,getlengthscales(k))
end

function kappa(k::RBFKernel{T,ARDKernel}) where {T<:Real,KT}
    return z->rbfkernel(z)
end

function updateweights!(k::RBFKernel{T,KT},w::Vector{T}) where {T,KT}
    k.fields.metric.weights .= 1.0./(w.^2)
end

function computeIndPointsJmm(k::RBFKernel{T,KT},X::Matrix{T},iPoint::Integer,K::Symmetric{T,Matrix{T}}) where {T,KT}
    l2 = (getlengthscales(k)).^2
    return -((X[iPoint,:]'.-X)./l2').*K[:,iPoint]
end

function computeIndPointsJnm(k::RBFKernel{T,KT},X::Matrix{T},x::Vector{T},iPoint::Integer,K::Matrix{T}) where {T,KT}
    l2 = (getlengthscales(k)).^2
    return -((x'.-X)./l2').*K[:,iPoint]
end
