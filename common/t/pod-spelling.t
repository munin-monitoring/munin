use Test::More;

plan skip_all => 'set TEST_POD_SPELLING to enable this test' unless $ENV{TEST_POD_SPELLING};

eval 'use Test::Spelling';
plan (
    skip_all => "Test::Spelling required for testing POD spelling"
) if $@;

add_stopwords(<DATA>);
all_pod_files_spelling_ok();

__END__
STARTTLS
TLS
