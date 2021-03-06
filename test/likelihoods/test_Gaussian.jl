using AugmentedGaussianProcesses
using Test

include("../testingtools.jl")

N,d = 100,2
k = transform(SqExponentialKernel(),10.0)
σ = 0.1
X,f = generate_f(N,d,k)
y = f + σ*randn(N)
floattypes = [Float64]
@testset "Gaussian Likelihood" begin
    @testset "GP" begin
        for floattype in floattypes
            @test typeof(GP(X,y,k)) <: GP{floattype,GaussianLikelihood{floattype},Analytic{floattype},1}
            model = GP(X,y,k,opt_noise=true,verbose=0)
            L = ELBO(model)
            @test train!(model,10)
            @test L < ELBO(model)
            @test testconv(model,"Regression",X,f,y)
            @test all(proba_y(model,X)[2].>0)
        end
    end
    @testset "VGP" begin
        @test_throws AssertionError VGP(X,y,k,GaussianLikelihood(),AnalyticVI())
        @test_throws AssertionError VGP(X,y,k,GaussianLikelihood(),QuadratureVI())
        @test_throws AssertionError VGP(X,y,k,GaussianLikelihood(),MCIntegrationVI())
    end
    @testset "SVGP" begin
        for floattype in floattypes
            @testset "AnalyticVI" begin
                model = SVGP(X,y,k,GaussianLikelihood(),AnalyticVI(),10,optimiser=false,verbose=0)
                @test typeof(model) <: SVGP{floattype,GaussianLikelihood{floattype},AnalyticVI{floattype,1},1}
                model_opt = SVGP(X,y,k,GaussianLikelihood(opt_noise=true),AnalyticVI(),10,optimiser=true,Zoptimiser=true,verbose=0)
                tests(model,model_opt,X,f,y,"Regression")
            end
            @test_throws AssertionError SVGP(X,y,k,GaussianLikelihood(),QuadratureVI(),20)
            @test_throws AssertionError SVGP(X,y,k,GaussianLikelihood(),MCIntegrationVI(),20)
        end
    end
    @testset "MCGP" begin
        # @test_throws AssertionError SVGP(X,y,k,GaussianLikelihood(),MCIntegrationVI(),20)
    end
end
