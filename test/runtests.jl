using AugmentedGaussianProcesses; const AGP = AugmentedGaussianProcesses
using Test
using Random: seed!
seed!(42)

AGP.setadbackend(:reverse_diff)
# Global flags for the tests
@testset "Test for AugmentedGaussianProcesses" begin
include("test_prior.jl")
include("test_likelihoods.jl")
# include("test_analyticVI.jl")
# include("test_GP.jl")
# include("test_VGP.jl")
# include("test_SVGP.jl")
# include("test_OnlineSVGP.jl")
# @test include("test_IO.jl")
end
