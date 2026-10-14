{
  pkgs,
  lib,
  helium,
}:
let
  fontPackages = [
    pkgs.noto-fonts-cjk-sans-static
    pkgs.noto-fonts-cjk-serif-static
  ];
in
pkgs.dockerTools.streamLayeredImage {
  name = "helium-cdp";
  tag = helium.version;
  maxLayers = 100;

  contents = [
    helium
    pkgs.dockerTools.fakeNss
    pkgs.dockerTools.usrBinEnv
  ]
  ++ fontPackages
  ++ [
    pkgs.bashNonInteractive
    pkgs.coreutils
    pkgs.socat
    pkgs.tini
  ];

  extraCommands = ''
    mkdir -p etc tmp
    chmod 1777 tmp
    printf 'hosts: files dns\npasswd: files\ngroup: files\n' > etc/nsswitch.conf
  '';

  config = {
    Entrypoint = [
      "${pkgs.tini}/bin/tini"
      "--"
      "${../image/run.sh}"
    ];
    ExposedPorts = {
      "9222/tcp" = { };
      "9223/tcp" = { };
    };
    Env = [
      "LANG=C.UTF-8"
      "LANGUAGE=C.UTF-8"
      "LC_ALL=C.UTF-8"
      "HOME=/tmp"
      "XDG_CONFIG_HOME=/tmp/xdg-config"
      "XDG_CACHE_HOME=/tmp/xdg-cache"
      "FONTCONFIG_FILE=${
        pkgs.makeFontsConf {
          fontDirectories = fontPackages;
          includes = [
            (pkgs.linkFarm "cjk-fontconf" [
              {
                name = "cjk.conf";
                path = ../image/fonts/cjk.conf;
              }
            ])
          ];
        }
      }"
      "HELIUM_DEFAULT_LISTS=${../image/ublock/filter-lists.txt}"
      "HELIUM_VERSION=${helium.version}"
      "PATH=${
        lib.makeBinPath [
          helium
          pkgs.coreutils
          pkgs.bashNonInteractive
          pkgs.socat
        ]
      }"
    ];
    Labels = {
      "org.opencontainers.image.title" = "helium-cdp";
      "org.opencontainers.image.description" =
        "Headless Helium with Chrome DevTools Protocol and CJK fonts";
      "org.opencontainers.image.source" = "https://github.com/9bingyin/helium-cdp";
      "org.opencontainers.image.version" = helium.version;
    };
  };

  passthru = {
    heliumVersion = helium.version;
  };

  meta = {
    description = "Headless Helium with Chrome DevTools Protocol";
    homepage = "https://github.com/9bingyin/helium-cdp";
    license = lib.licenses.mit;
  };
}
