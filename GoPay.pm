package Koha::Plugin::Com::RBitTechnology::GoPay;

use Modern::Perl;
use base qw(Koha::Plugins::Base);
use utf8;
use C4::Context;
use Koha::Patrons;

use Data::Dumper;

our $VERSION = "1.0.0";

our $metadata = {
    name            => 'Platební brána GoPay',
    author          => 'Radek Šiman',
    description     => 'Toto rozšíření poskytuje podporu online plateb s využitím brány GoPay.',
    date_authored   => '2018-01-09',
    date_updated    => '2018-01-09',
    minimum_version => '17.11',
    maximum_version => undef,
    version         => $VERSION
};

sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual $self
    my $self = $class->SUPER::new($args);

    return $self;
}

sub opac_online_payment {
    my ( $self, $args ) = @_;

    return 1;
}

sub opac_online_payment_begin {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my ( $template, $borrowernumber ) = get_template_and_user(
        {   template_name   => abs_path( $self->mbf_path( 'opac_online_payment_begin.tt' ) ),
            query           => $cgi,
            type            => 'opac',
            authnotrequired => 1,
            is_plugin       => 1,
        }
    );

}

sub opac_online_payment_end {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};
}

sub install() {
    return 1;
}

sub uninstall() {
    return 1;
}
