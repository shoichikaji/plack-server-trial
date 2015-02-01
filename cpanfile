requires 'perl', '5.008001';
requires 'Plack';
requires 'HTTP::Parser::XS';
requires 'HTTP::Status';
requires 'Data::Dump';

on 'test' => sub {
    requires 'Test::More', '0.98';
};

