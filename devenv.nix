{pkgs, ...}: {
  packages = with pkgs; [
    just
    stylua
    selene
    perl
  ];
  languages.rust = {
    enable = true;
    channel = "stable";
  };
  languages.lua.enable = true;
}
