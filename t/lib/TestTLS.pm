#!/usr/bin/perl
# Generate test TLS certificates at test time.
# Replaces committed PEM files that may be stale.

use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Path qw(make_path remove_tree);

sub generate_test_certs {
    my ($dir) = @_;
    $dir //= tempdir("tls-XXXXXX", TMPDIR => 1);

    my $ca_dir = "$dir/CA";
    make_path($ca_dir);

    # Generate CA
    system("openssl genrsa -out $ca_dir/ca_key.pem 2048 2>/dev/null");
    system("openssl req -new -x509 -key $ca_dir/ca_key.pem -out $ca_dir/ca_cert.pem -days 3650 -subj '/C=US/ST=Test/L=Test/O=Munin Test CA/CN=Munin Test CA' 2>/dev/null");

    # Generate valid server cert
    _generate_cert($dir, "master", "master", 365);

    # Generate valid client cert
    _generate_cert($dir, "node", "node", 365);

    # Generate expired cert using faketime if available
    if (system("which faketime >/dev/null 2>&1") == 0) {
        _generate_cert($dir, "expired", "expired", -365, "2025-01-01 00:00:00");
    }

    return $dir;
}

sub _generate_cert {
    my ($dir, $name, $cn, $days, $faketime) = @_;

    my $key = "$dir/${name}_key.pem";
    my $csr = "$dir/${name}_csr.pem";
    my $cert = "$dir/${name}_cert.pem";
    my $ext = "$dir/${name}_ext.cnf";
    my $ca_cert = "$dir/CA/ca_cert.pem";
    my $ca_key = "$dir/CA/ca_key.pem";

    # Generate key
    system("openssl genrsa -out $key 2048 2>/dev/null");

    # Generate CSR
    system("openssl req -new -key $key -out $csr -subj '/C=US/ST=Test/L=Test/O=Munin Test/CN=${cn}.testing.acme.com' 2>/dev/null");

    # Create SAN extension
    open my $fh, '>', $ext or die "Cannot write $ext: $!";
    print $fh "[v3_req]\n";
    print $fh "basicConstraints = CA:FALSE\n";
    print $fh "keyUsage = digitalSignature, keyEncipherment\n";
    print $fh "subjectAltName = DNS:${cn}.testing.acme.com,DNS:testing.acme.com,IP:127.0.0.1\n";
    close $fh;

    # Sign with CA
    my $cmd;
    if ($faketime) {
        $cmd = "faketime '$faketime' openssl x509 -req -in $csr -CA $ca_cert -CAkey $ca_key -CAcreateserial -out $cert -days $days -extfile $ext -extensions v3_req 2>/dev/null";
    } else {
        $cmd = "openssl x509 -req -in $csr -CA $ca_cert -CAkey $ca_key -CAcreateserial -out $cert -days $days -extfile $ext -extensions v3_req 2>/dev/null";
    }
    system($cmd);

    # Cleanup temp files
    unlink $csr, $ext;
}

1;
