package Koha::Plugin::Com::Theke::SLNP;

# Copyright 2021 Theke Solutions
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# This program comes with ABSOLUTELY NO WARRANTY;

use Modern::Perl;

use base qw(Koha::Plugins::Base);

use List::MoreUtils qw(any);
use Mojo::JSON qw(decode_json encode_json);
use YAML;

use Koha::Biblioitems;
use Koha::Items;

use Koha::Plugin::Com::Theke::SLNP::Exceptions;

our $VERSION = "{VERSION}";

our $metadata = {
    name            => 'SLNP ILL connector plugin for Koha',
    author          => 'Theke Solutions',
    date_authored   => '2018-09-10',
    date_updated    => "1980-06-18",
    minimum_version => '20.1100000',
    maximum_version => undef,
    version         => $VERSION,
    description     => 'SLNP ILL connector plugin for Koha'
};

=head1 Koha::Plugin::Com::Theke::SLNP

SLNP ILL connector plugin for Koha

=head2 Plugin methods

=head3 new

Constructor:

    my $plugin = Koha::Plugin::Com::Theke::SLNP->new;

=cut

sub new {
    my ( $class, $args ) = @_;

    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    my $self = $class->SUPER::new($args);

    return $self;
}

=head3 configure

Plugin configuration method

=cut

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $template = $self->get_template({ file => 'configure.tt' });

    unless ( scalar $cgi->param('save') ) {

        ## Grab the values we already have for our settings, if any exist
        $template->param(
            configuration => $self->retrieve_data('configuration'),
        );

        $self->output_html( $template->output() );
    }
    else {
        $self->store_data(
            {
                configuration => scalar $cgi->param('configuration'),
            }
        );
        $template->param(
            configuration => $self->retrieve_data('configuration'),
        );
        $self->output_html( $template->output() );
    }
}

=head3 configuration

Accessor for the de-serialized plugin configuration

=cut

sub configuration {
    my ($self) = @_;

    my $configuration;
    eval { $configuration = YAML::Load( $self->retrieve_data('configuration') // '' . "\n\n" ); };
    die($@) if $@;

    return $configuration;
}

1;

