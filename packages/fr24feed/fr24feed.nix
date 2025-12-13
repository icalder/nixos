{ stdenv, lib }:

let
  binaries = if stdenv.isAarch64 then "rpi_binaries" else "linux_binaries";
  platform = if stdenv.isAarch64 then "arm64" else "i386";
in

stdenv.mkDerivation rec {
  pname = "fr24feed";
  version = "1.0.54-0";

  # Binaries are available at:
  # https://repo-feed.flightradar24.com/rpi_binaries/fr24feed_1.0.54-0_arm64.tgz
  # https://repo-feed.flightradar24.com/linux_binaries/fr24feed_1.0.54-0_i386.tgz
  src = fetchTarball {
    url = "https://repo-feed.flightradar24.com/${binaries}/fr24feed_${version}_${platform}.tgz";
    sha256 =
      if stdenv.isAarch64 then
        "sha256:06lpcbhzyq5z15bz5x6x0aiswscw39wqk32lan6ia6hmrjh5vyw3"
      else
        "sha256:1l4az6p51sm0g4l8vbvnr65y792lakwp4jmkihpsvrfg3a8inpg1";
  };

  installPhase = ''
    mkdir -p $out/bin
    cp fr24feed $out/bin/

    cat > $out/bin/fr24feed-signup-adsb <<EOF
    #!${stdenv.shell}
    $out/bin/fr24feed --signup --adsb --config-file=./fr24feed.ini
    EOF

    chmod +x $out/bin/fr24feed-signup-adsb
  '';

  meta = {
    description = "Flight tracking software for receiving and decoding ADS-B signals";
    homepage = "https://www.flightradar24.com/share-your-data";
    license = lib.licenses.gpl2Plus; # Explicitly use lib.licenses
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };

}
