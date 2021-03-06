"""
Solve any non-conjugate likelihood using Variational Inference
by making a numerical approximation (quadrature or MC integration)
of the expected log-likelihood ad its gradients
Gradients are computed as in "The Variational Gaussian Approximation
Revisited" by Opper and Archambeau 2009
"""
abstract type NumericalVI{T<:Real} <: VariationalInference{T} end

include("quadratureVI.jl")
include("MCVI.jl")

isnatural(vi::NumericalVI) = vi.NaturalGradient

""" `NumericalVI(integration_technique::Symbol=:quad;ϵ::T=1e-5,nMC::Integer=1000,nGaussHermite::Integer=20,optimiser=Momentum(0.001))`

General constructor for Variational Inference via numerical approximation.

**Argument**

    -`integration_technique::Symbol` : Method of approximation can be `:quad` for quadrature see [QuadratureVI](@ref) or `:mc` for MC integration see [MCIntegrationVI](@ref)

**Keyword arguments**

    - `ϵ::T` : convergence criteria, which can be user defined
    - `nMC::Int` : Number of samples per data point for the integral evaluation (for the MCIntegrationVI)
    - `nGaussHermite::Int` : Number of points for the integral estimation (for the QuadratureVI)
    - `natural::Bool` : Use natural gradients
    - `optimiser` : Optimiser used for the variational updates. Should be an Optimiser object from the [Flux.jl](https://github.com/FluxML/Flux.jl) library, see list here [Optimisers](https://fluxml.ai/Flux.jl/stable/training/optimisers/) and on [this list](https://github.com/theogf/AugmentedGaussianProcesses.jl/tree/master/src/inference/optimisers.jl). Default is `Momentum(0.001)`
"""
function NumericalVI(integration_technique::Symbol=:quad;ϵ::T=1e-5,nMC::Integer=1000,nGaussHermite::Integer=20,optimiser=Momentum(1e-3),natural::Bool=true) where {T<:Real}
    if integration_technique == :quad
        QuadratureVI{T}(ϵ,nGaussHermite,optimiser,false,0,natural)
    elseif integration_technique == :mc
        MCIntegrationVI{T}(ϵ,nMC,optimiser,false,0,natural)
    else
        @error "Only possible integration techniques are quadrature : :quad or mcmc integration :mcmc"
    end
end

""" `NumericalSVI(integration_technique::Symbol=:quad;ϵ::T=1e-5,nMC::Integer=1000,nGaussHermite::Integer=20,optimizer=Momentum(0.001))`

General constructor for Stochastic Variational Inference via numerical approximation.

**Argument**

    - `nMinibatch::Integer` : Number of samples per mini-batches
    - `integration_technique::Symbol` : Method of approximation can be `:quad` for quadrature see [QuadratureVI](@ref) or `:mc` for MC integration see [MCIntegrationVI](@ref)

**Keyword arguments**

    - `ϵ::T` : convergence criteria, which can be user defined
    - `nMC::Int` : Number of samples per data point for the integral evaluation (for the MCIntegrationVI)
    - `nGaussHermite::Int` : Number of points for the integral estimation (for the QuadratureVI)
    - `natural::Bool` : Use natural gradients
    - `optimiser` : Optimiser used for the variational updates. Should be an Optimiser object from the [Flux.jl](https://github.com/FluxML/Flux.jl) library, see list here [Optimisers](https://fluxml.ai/Flux.jl/stable/training/optimisers/) and on [this list](https://github.com/theogf/AugmentedGaussianProcesses.jl/tree/master/src/inference/optimisers.jl). Default is `Momentum(0.001)`
"""
function NumericalSVI(nMinibatch::Integer,integration_technique::Symbol=:quad;ϵ::T=1e-5,nMC::Integer=200,nGaussHermite::Integer=20,optimiser=Momentum(1e-3),natural::Bool=true) where {T<:Real}
    if integration_technique == :quad
        QuadratureVI{T}(ϵ,nGaussHermite,optimizer,true,nMinibatch,natural)
    elseif integration_technique == :mc
        MCIntegrationVI{T}(ϵ,nMC,optimizer,true,nMinibatch,natural)
    else
        @error "Only possible integration techniques are quadrature : :quad or mcmc integration :mc"
    end
end

function Base.show(io::IO,inference::NumericalVI{T}) where T
    print(io,"$(inference.Stochastic ? "Stochastic numerical" : "Numerical") inference by $(isa(inference,MCIntegrationVI) ? "Monte Carlo Integration" : "Quadrature")")
end

∇E_μ(::Likelihood,i::NVIOptimizer,::AbstractVector) = (-i.ν,)
∇E_Σ(::Likelihood,i::NVIOptimizer,::AbstractVector) = (0.5.*i.λ,)

function variational_updates!(model::AbstractGP{T,L,<:NumericalVI}) where {T,L}
    compute_grad_expectations!(model)
    classical_gradient!.(
        ∇E_μ(model.likelihood,model.inference.vi_opt[1],[]),
        ∇E_Σ(model.likelihood,model.inference.vi_opt[1],[]),
        model.inference, model.inference.vi_opt,
        get_Z(model), model.f)
    if isnatural(model.inference)
        natural_gradient!.(model.f, model.inference.vi_opt)
    end
    global_update!(model)
end

function classical_gradient!(∇E_μ::AbstractVector{T},∇E_Σ::AbstractVector{T}, i::NumericalVI, opt::NVIOptimizer, X::AbstractMatrix, gp::_VGP{T}) where {T<:Real}
    opt.∇η₂ .= Diagonal(∇E_Σ) - 0.5 * (inv(gp.K).mat - inv(gp.Σ))
    opt.∇η₁ .= ∇E_μ - gp.K \ (gp.μ - gp.μ₀(X))
end

function classical_gradient!(∇E_μ::AbstractVector{T},∇E_Σ::AbstractVector{T}, i::NumericalVI, opt::NVIOptimizer, Z::AbstractMatrix, gp::_SVGP{T}) where {T<:Real}
    opt.∇η₂ .= i.ρ * transpose(gp.κ) * Diagonal(∇E_Σ) * gp.κ - 0.5 * (inv(gp.K).mat - inv(gp.Σ))
    opt.∇η₁ .= i.ρ * transpose(gp.κ) * ∇E_μ - gp.K \ (gp.μ - gp.μ₀(Z))
end

function natural_gradient!(gp::Abstract_GP{T},opt::NVIOptimizer) where {T}
    opt.∇η₂ .= 2*gp.Σ*opt.∇η₂*gp.Σ
    opt.∇η₁ .= gp.K*opt.∇η₁
end

function global_update!(model::AbstractGP{T,L,<:NumericalVI}) where {T,L}
    for (gp,opt) in zip(model.f,model.inference.vi_opt)
        Δ1 = Optimise.apply!(opt.optimiser,gp.μ,opt.∇η₁)
        Δ2 = Optimise.apply!(opt.optimiser,gp.Σ,opt.∇η₂)
        gp.μ .+= Δ1
        α = 1.0
        while !isposdef(gp.Σ+α*Symmetric(Δ2)) && α > 1e-8
            α *= 0.5
        end
        if α > 1e-8
            gp.Σ .+= α*Symmetric(Δ2)
        else
            @warn "α was too small for update" maxlog=10
        end
        # global_update!.(model.f)
    end
end

## ELBO

expec_log_likelihood(l::Likelihood,i::NumericalVI,y,μ::Tuple{<:AbstractVector{T}},Σ::Tuple{<:AbstractVector{T}}) where {T} = expec_log_likelihood(l,i,y,first(μ),first(Σ))

function ELBO(model::AbstractGP{T,L,<:NumericalVI}) where {T,L}
    tot = zero(T)
    tot += model.inference.ρ*expec_log_likelihood(model.likelihood,model.inference,get_y(model),mean_f(model),diag_cov_f(model))
    tot -= GaussianKL(model)
    tot -= extraKL(model)
end
