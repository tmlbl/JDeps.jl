__precompile__()

module JVM

using JSON, Mustache

local_dir = ""
package_dir = "/tmp/.jvm"
archive_name = ".jvm.tar.gz"
JULIA_VERSION = ""
const DEFAULT_VERSION = v"0.4.5"
const CONFIG_FILE = "jvm.json"

include("util.jl")
include("getbinary.jl")
include("Config.jl")
include("tasks.jl")
include("cli.jl")
include("legacy.jl")

# Localize the package directory
function localize()
  if isfile(CONFIG_FILE)
    global config = getconfig()
  end
  ENV["JULIA_PKGDIR"] = local_dir
  global JULIA_VERSION = "v$(VERSION.major).$(VERSION.minor)"
  run(`mkdir -p $(ENV["JULIA_PKGDIR"])`)
end

function __init__()
  global JULIA_PKGDIR_ORIG = Pkg.dir()
  global local_dir = joinpath(pwd(), ".jvm")
  update_env()
end

end # module
