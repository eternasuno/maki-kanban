{pkgs, ...}: {
  packages = with pkgs; [
    just
    stylua
    selene
  ];
  languages.rust = {
    enable = true;
    channel = "stable";
  };
  languages.lua.enable = true;
}
