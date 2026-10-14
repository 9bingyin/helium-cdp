{
  pkgs,
  lib,
  helium-bin,
}:
let
  fontPackages = [
    pkgs.noto-fonts-cjk-sans-static
    pkgs.noto-fonts-cjk-serif-static
  ];
  helium =
    pkgs.runCommand "helium-${helium-bin.version}" { nativeBuildInputs = [ pkgs.makeBinaryWrapper ]; }
      ''
        mkdir -p $out/bin
        makeBinaryWrapper ${helium-bin.unwrapped}/bin/helium $out/bin/helium \
          --set CHROME_WRAPPER "$out/bin/helium" \
          --add-flag "--simulate-outdated-no-au=Tue, 31 Dec 2099 23:59:59 GMT"
      '';
in
pkgs.dockerTools.streamLayeredImage {
  name = "helium-cdp";
  tag = helium-bin.version;
  maxLayers = 20;

  contents = [
    helium
    pkgs.dockerTools.fakeNss
    pkgs.dockerTools.usrBinEnv
  ]
  ++ fontPackages
  ++ [
    pkgs.bashNonInteractive
    pkgs.coreutils
    pkgs.realm
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
      "HELIUM_VERSION=${helium-bin.version}"
      "PATH=${
        lib.makeBinPath [
          helium
          pkgs.coreutils
          pkgs.bashNonInteractive
          pkgs.realm
        ]
      }"
    ];
    Labels = {
      "org.opencontainers.image.title" = "helium-cdp";
      "org.opencontainers.image.description" =
        "Headless Helium with Chrome DevTools Protocol and CJK fonts";
      "org.opencontainers.image.source" = "https://github.com/9bingyin/helium-cdp";
      "org.opencontainers.image.version" = helium-bin.version;
    };
  };

  passthru = {
    heliumVersion = helium-bin.version;
  };

  meta = {
    description = "Headless Helium with Chrome DevTools Protocol";
    homepage = "https://github.com/9bingyin/helium-cdp";
    license = lib.licenses.mit;
  };
}
