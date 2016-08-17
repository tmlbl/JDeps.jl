# EXPERIMENTAL
# If a package contains a jvm.json, run its tests on multiple versions of julia
function test(args)
  test_dir = "/tmp/.jdeps.test"
  if length(args) < 1
    if isfile("test/runtests.jl")
      jevaluate(getconfig(), "include(\"test/runtests.jl\")")
      exit()
    else
      println(STDERR, "usage: \n\ttest <pkg> <?julia_version>")
      exit(1)
    end
  end
  test_pkg = Pkg.dir(args[1])
  if isdir(test_dir)
    bashevaluate("rm -rf $test_dir")
  end
  ENV["JULIA_PKGDIR"] = test_dir
  cfg = Config()
  if length(args) == 2
    cfg.julia = VersionNumber(args[2])
  end
  pkg_dir = "$(ENV["JULIA_PKGDIR"])/v$(cfg.julia.major).$(cfg.julia.minor)/$(args[1])"

  jevaluate(cfg, "Pkg.init()")

  # HACK - use clone to install dependencies, then copy the most recent code
  jevaluate(cfg, "Pkg.clone(\"$test_pkg\")")
  bashevaluate("rm -rf $pkg_dir; cp -r $test_pkg $pkg_dir")

  jevaluate(cfg, "Pkg.test(\"$(args[1])\")")
  info("Removing $(ENV["JULIA_PKGDIR"])")
  run(`rm -rf $(ENV["JULIA_PKGDIR"])`)
end

function freeze(cfg::Config)
  deps = Array{Dep,1}()
  for (p, v) in Pkg.installed()
    ix = find(d -> d.name == p || namefromgit(d.name) == p, cfg.deps)
    if length(ix) == 0
      push!(deps, Dep(p, v))
    else
      dep = cfg.deps[ix[1]]
      if isgit(dep.name)
        push!(deps, Dep(dep.name, getsha(p)))
      else
        push!(deps, Dep(p, v))
      end
    end
  end
  cfg.deps = deps
  writeconfig(cfg)
end

function install_registered(dep::Dep)
  if !isdir(Pkg.dir(dep.name))
    Pkg.add(dep.name, dep.version)
  end
  v = Pkg.installed(dep.name)
  if v != dep.version
    Pkg.pin(dep.name, dep.version)
  end
end

function install_unregistered(dep::Dep)
  name = namefromgit(dep.name)
  if !isdir(Pkg.dir(name))
    Pkg.clone(dep.name)
  else
    gitcmd(name, "fetch --all -q")
  end
  gitcmd(name, "checkout $(dep.version) -q")
  info("Pinned $name at $(dep.version)")
  Pkg.build(name)
end

function install(cfg::Config)
  meta = ENV["JULIA_PKGDIR"]*"/$JULIA_VERSION/METADATA"
  if !isdir(meta)
    jevaluate(cfg, "Pkg.init()")
  end
  for d in cfg.deps
    if isgit(d.name)
      install_unregistered(d)
    else
      install_registered(d)
    end
  end
end

const docker_template =
    Mustache.template_from_file(joinpath(dirname(@__FILE__), "Dockerfile"))

function image(cfg)
  if cfg.baseImg == ""
    cfg.baseImg = "julia:$(cfg.julia)"
  end
  precomp = join(map(n -> "using $n", map(d -> namefromgit(d.name), cfg.deps)), ';')
  cfg.postBuild *= "\nRUN julia -e \"$precomp\""
  Dockerfile = Mustache.render(docker_template, cfg)
  dfilepath = "$local_dir/Dockerfile"
  last_built_file = joinpath(local_dir, "last-built.json")
  # Only rebuild base if a change has been made to config
  if isfile(last_built_file)
    last_built = readall(open(last_built_file))
    this_config = readall(open(CONFIG_FILE))
    should_build_base = (last_built != this_config)
  else
    should_build_base = true
  end

  if should_build_base
    install(cfg)
    package(cfg)
    if isfile(dfilepath)
      rm(dfilepath)
    end
    f = open("$local_dir/Dockerfile", "w")
    write(f, Dockerfile)
    close(f)
    base_img_name = "$(cfg.name)-base:latest"
    bashevaluate("docker build -t $base_img_name -f $dfilepath .")
    # Squash the base image, if possible
    should_squash = true
    try
      readall(`docker-squash -h`)
    catch err
      warn("docker-squash not installed. Install it for smaller image sizes.")
      should_squash = false
    end
    if should_squash
      info("Squashing $base_img_name")
      run(`docker-squash -t $base_img_name $base_img_name`)
    end
    info("Built image $base_img_name")
    # Store the config that was built
    cp(CONFIG_FILE, last_built_file; remove_destination=true)
  end

  if isfile("Dockerfile")
    bashevaluate("docker build -t $(cfg.name):$(cfg.version) .")
    info("Built image $(cfg.name):$(cfg.version)")
    # Tag the newly built image as latest
    run(`docker tag $(cfg.name):$(cfg.version) $(cfg.name):latest`)
  end
end

function package(cfg::Config)
  if isfile(archive_name)
    rm(archive_name)
  end
  info("Copying files...")
  if isdir(package_dir)
    rm(package_dir; recursive=true)
  end
  cp(local_dir, package_dir)

  info("Cleaning package sources...")
  run(`rm -rf $package_dir/.cache/*`)

  ENV["JULIA_PKGDIR"] = package_dir
  # Remove Homebrew, in case we are on a Mac
  if isdir(Pkg.dir("Homebrew"))
    rm(Pkg.dir("Homebrew"); recursive=true)
  end
  # Remove all submodules, they may contain incompatible artifacts
  cur_dir = pwd()
  for p in readdir(Pkg.dir())
    path = joinpath(Pkg.dir(), p)
    if isdir(path)
      cd(path)
      paths = map((ln) -> split(chomp(ln)), readlines(`git submodule`))
      for sub in paths
        rm(joinpath(Pkg.dir(p), sub[2]); recursive=true)
      end
    end
  end

  for p in Pkg.installed()
    gitclean(p[1])
  end

  info("Creating tarball...")
  cd(cur_dir)
  run(`tar -czf $archive_name -C /tmp .jvm`)
end



function update(cfg::Config)
  jevalfile(cfg, joinpath(dirname(@__FILE__), "../scripts/update.jl"))
end
