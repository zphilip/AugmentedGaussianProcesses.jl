using Distributions
using LinearAlgebra
using Profile, ProfileView
using OMGP
doPlots = true
if doPlots
    using Plots
    pyplot()
end
N_data = 500;N_test = 20
N_indpoints = 20; N_dim = 2
noise = 2.0
minx=-5.0; maxx=5.0
function latent(x)
    return x[:,1].*sin.(1.0*x[:,2])
end
X = rand(N_data,N_dim)*(maxx-minx).+minx
x_test = range(minx,stop=maxx,length=N_test)
X_test = hcat([j for i in x_test, j in x_test][:],[i for i in x_test, j in x_test][:])
y = sign.(latent(X)+rand(Normal(0,noise),size(X,1)))
y_test = sign.(latent(X_test)+rand(Normal(0,noise),size(X_test,1)))



kernel = RBFKernel([3.0],dim=N_dim)
fullm = !true
sparsem = true
ps = []; t_full = 0; t_sparse = 0; t_stoch = 0;
if fullm
    println("Testing the full model")
    t_full = @elapsed fullmodel = OMGP.BatchXGPC(X,y,noise=noise,kernel=kernel,verbose=3,Autotuning=true)
    t_full += @elapsed fullmodel.train(iterations=20)
    y_full = fullmodel.predictproba(X_test); acc_full = 1-sum(abs.(sign.(y_full.-0.5)-y_test))/(2*length(y_test))
    save_trained_model("test/fullXGPC_test.jld2",fullmodel)
    fmodel = load_trained_model("test/fullXGPC_test.jld2")
    y_full2 = fmodel.predictproba(X_test)
    if mean(abs.(y_full-y_full2))>1e-5
        return false
    end
end
# save_trained_model("test/fullXGPC_test.jld2",fullmodel)
# # #### SPARSE MODEL EVALUATION ####
if sparsem
    println("Testing the sparse model")
    t_sparse = @elapsed sparsemodel = OMGP.SparseXGPC(X,y,Stochastic=false,Autotuning=true,ϵ=1e-6,verbose=3,m=N_indpoints,noise=1e-10,kernel=kernel,OptimizeIndPoints=false)
    metrics,savelog = OMGP.getLog(sparsemodel,X_test=X_test,y_test=y_test)
    t_sparse += @elapsed sparsemodel.train(iterations=10)#,callback=savelog)
    y_sparse = sparsemodel.predictproba(X_test); acc_sparse = 1-sum(abs.(sign.(y_sparse.-0.5)-y_test))/(2*length(y_test))
    save_trained_model("test/sparseXGPC_test.jld2",sparsemodel)
    smodel = load_trained_model("test/sparseXGPC_test.jld2")
    y_sparse2 = smodel.predictproba(X_test)
    if mean(abs.(y_sparse-y_sparse2))>1e-5
        return false
    end
end
