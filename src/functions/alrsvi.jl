mutable struct ALRSVI <: Optimizer
    opt_type::String
    t::Int64
    g::AbstractArray
    h::Float64
    τ::Float64
    ρ::Float64
end

""" Construct Adaptive Learning Rate for Stochastic Variational Inference"""
function ALRSVI(;τ::Int=100)
    ALRSVI("Adaptive Learning Rate for Stochastic Variational Inference",0,[0.0],0.0,τ,-1.0)
end

GradDescent.params(opt::ALRSVI) = "ρ=$(opt.ρ)"

function init!(inference::Inference{T},model::SVGP) where T
    n_repeat = ceil(inference.optimizer_η₁[1].τ/model.inference.nSamplesUsed)
    for n_s in 1:n_repeat
        model.inference.MBIndices = StatsBase.sample(1:model.inference.nSamples,inference.nSamplesUsed,replace=false)
        computeMatrices!(model)
        local_updates!(model)
        natural_gradient!(model)
        if n_s == 1
            for (i,opt) in enumerate(inference.optimizer_η₁)
                opt.g = inference.∇η₁[i]./n_repeat
            end
            for (i,opt) in enumerate(inference.optimizer_η₂)
                opt.g = Array(inference.∇η₂[i])./n_repeat
            end
        else
            for (i,opt) in enumerate(inference.optimizer_η₁)
                opt.g .+= inference.∇η₁[i]./n_repeat
            end
            for (i,opt) in enumerate(inference.optimizer_η₂)
                opt.g .+= Array(inference.∇η₂[i])./n_repeat
            end
        end
    end
    for (i,opt) in enumerate(inference.optimizer_η₁)
        opt.τ = inference.nSamplesUsed*10
        opt.h = dot(opt.g,opt.g)
        opt.ρ = dot(opt.g,opt.g)/opt.h
    end
    for (i,opt) in enumerate(inference.optimizer_η₂)
        opt.τ = inference.nSamplesUsed*10
        opt.h = dot(opt.g,opt.g)
        opt.ρ = dot(opt.g,opt.g)/opt.h
    end
end

function GradDescent.update(opt::ALRSVI, g_t::AbstractArray{T,N}) where {T<:Real,N}
    # update timestep
    if opt.ρ < 0
        @error "Optimizer has not been initialized externally, it needs a special initialization"
    end
    opt.t += 1
    opt.g .= (1.0-1.0/opt.τ).*opt.g + 1.0/opt.τ .* g_t
    opt.h = (1.0-1.0/opt.τ).*opt.h + 1.0/opt.τ .* dot(g_t,g_t)
    opt.ρ = dot(opt.g,opt.g)/opt.h
    opt.τ = opt.τ*(1-opt.ρ)+1.0
    return opt.ρ * g_t
end
