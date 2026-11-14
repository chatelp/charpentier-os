# The disk's password screen (docs/DESIGN.md §4.12 « Verrouillage »): Plymouth
# in the initrd, under systemd, with a script theme (charpentier.script). Why
# Plymouth: systemd-cryptsetup asks it for the password, the screen is drawn
# with a real font, and the console's keyboard (console.keyMap, the layout
# chosen at installation) is the one Plymouth reads. Without it, the prompt is
# systemd's own English text on the console.
{ pkgs, ... }:
let
  # JetBrains Mono (SIL Open Font License 1.1, OFL.txt), the app's fixed pitch.
  font = "${pkgs.jetbrains-mono}/share/fonts/truetype/JetBrainsMono-Regular.ttf";

  theme = pkgs.runCommand "plymouth-theme-charpentier" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
    dir=$out/share/plymouth/themes/charpentier
    mkdir -p $dir
    cp ${./charpentier.script} $dir/charpentier.script
    cp ${./OFL.txt} $dir/OFL.txt
    # The inverted line's ground: one pixel of ink, stretched by the script.
    magick -size 1x1 xc:'#dfe3ea' $dir/ink.png
    cat > $dir/charpentier.plymouth <<EOF
    [Plymouth Theme]
    Name=Charpentier
    Description=Le mot de passe du disque, en chasse fixe sur #14161a
    ModuleName=script

    [script]
    ImageDir=$dir
    ScriptFile=$dir/charpentier.script
    EOF
  '';
in
{
  boot.plymouth = {
    enable = true;
    theme = "charpentier";
    themePackages = [ theme ];
    inherit font;
  };
}
