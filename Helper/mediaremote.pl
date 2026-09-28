#!/usr/bin/perl
# Charge MediaRemoteAdapter.dylib dans /usr/bin/perl (autorisé par mediaremoted)
# et lance la boucle de diffusion. Usage : perl mediaremote.pl <chemin du dylib>
use strict;
use warnings;
use DynaLoader;

my $lib = shift or die "usage: $0 <dylib>\n";
my $handle = DynaLoader::dl_load_file($lib, 0) or die "chargement: " . DynaLoader::dl_error() . "\n";
my $symbol = DynaLoader::dl_find_symbol($handle, "adapter_stream") or die "symbole introuvable\n";
DynaLoader::dl_install_xsub("main::adapter_stream", $symbol);
adapter_stream();
