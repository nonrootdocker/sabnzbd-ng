{
  description = "minimalbase-ng + sabnzbd service";

  inputs = {
    nixpkgs.follows = "minimalbase/nixpkgs";
    minimalbase.url = "github:nonrootdocker/minimalbase-ng";
    sabnzbd-src = {
      url = "github:sabnzbd/sabnzbd";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, minimalbase, sabnzbd-src }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
      };
    };
    # ----------------------------
    # SABnzbd Python environment
    # ----------------------------
    sabnzbdPython = pkgs.python3.withPackages (ps: [
      ps.apprise
      ps.babelfish
      ps.blinker
      ps.certifi
      ps.charset-normalizer
      ps.cheetah3
      ps.cheroot
      ps.cherrypy
      ps.configobj
      ps.cryptography
      ps.feedparser
      ps.guessit
      ps.idna
      ps.jaraco-classes
      ps.jaraco-collections
      ps.jaraco-context
      ps.jaraco-functools
      ps.jaraco-text
      ps.markdown
      ps.more-itertools
      ps.notify2
      ps.oauthlib
      ps.orjson
      ps.paho-mqtt
      ps.portend
      ps.puremagic
      ps.pycparser
      ps.pyjwt
      ps.pyopenssl
      ps.pysocks
      ps.python-dateutil
      ps.pytz
      ps.pyyaml
      ps.rarfile
      ps.rebulk
      ps.requests
      ps.requests-oauthlib
      ps.sabctools
      ps.sgmllib3k
      ps.six
      ps.tempora
      ps.ujson
      ps.urllib3
      ps.zc-lockfile
    ]);

    # ----------------------------
    # SABnzbd version: read from the source's own version.py (`__version__ = "X.Y.Z"`).
    # Exposed as the `version` output for CI tagging; matches whatever sabnzbd-src
    # is locked/overridden to.
    # ----------------------------
    sabnzbdVersion = pkgs.runCommand "sabnzbd-version" { } ''
      grep -oE '__version__ *= *"[^"]*"' ${sabnzbd-src}/sabnzbd/version.py \
        | head -n1 | sed -E 's/.*"([^"]*)".*/\1/' | tr -d '\n' > $out
    '';

    sabnzbd = pkgs.stdenv.mkDerivation {
      pname = "sabnzbd";
      version = "latest";
      src = sabnzbd-src;

      buildInputs = [ sabnzbdPython ];

      # Clean, standard install phase (no custom python symlink hacks needed)
      installPhase = ''
        mkdir -p $out/app
        cp -r . $out/app/sabnzbd
      '';
    };

    # ----------------------------
    # ABI generator (Points directly to Nix Store)
    # ----------------------------
    sabAbi = pkgs.writeTextFile {
      name = "sabnzbd-abi.json";
      text = builtins.toJSON {
        version = 2;
        process = {
          # Point directly to the secure, immutable Nix store Python binary:
          exec = "${sabnzbdPython}/bin/python"; 
          args = [
            "/app/sabnzbd/SABnzbd.py"
            "--config-file"
            "/data/sabnzbd.ini"
            "--logging"
            "0"
            "--console"
            "--browser"
            "0"
          ];
        };
      };
      destination = "/app/main"; 
    };

  in {
    packages.${system} = {
      default = self.packages.${system}.sabnzbd-image;
      version = sabnzbdVersion;
      sabnzbd-image = pkgs.dockerTools.buildImage {
        name = "sabnzbd";
        tag = "latest";
        fromImage = minimalbase.packages.${system}.base-image;

        copyToRoot = pkgs.buildEnv {
          name = "root";
          paths = [
            pkgs.coreutils
            pkgs.tzdata
            pkgs.cacert
            pkgs.par2cmdline
            pkgs.unrar
            pkgs.p7zip

            sabnzbd
            sabAbi
          ];
        };

        config = {
          Entrypoint = [ "${minimalbase.packages.${system}.container-init}/bin/container-init" ];

          User = "1000:1000";

          Env = [
            "PATH=/bin"
            "TZ=UTC"
            "LANG=en_US.UTF-8"
          ];
        };
      };
    };
  };
}
