using JVM,
      FactCheck

facts("git utils") do
  @fact !JVM.isgit("Compat") --> true
  @fact !JVM.isgit("AppConf") --> true
  @fact JVM.isgit("git@github.com:tmlbl/AppConf.jl") --> true
  @fact JVM.isgit("https://github.com/tmlbl/AppConf.jl") --> true
  @fact JVM.namefromgit("git@github.com:tmlbl/AppConf.jl.git") --> "AppConf"
  @fact JVM.namefromgit("https://github.com/tmlbl/AppConf.jl") --> "AppConf" 
end
