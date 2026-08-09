package SLNP::Commands::DatenAenderung;

#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use utf8;

use C4::Context;

use C4::Circulation;
use C4::Reserves;

use Koha::Database;

use Koha::Biblios;
use Koha::DateUtils qw(dt_from_string);
use Koha::ILL::Requests;
use Koha::Plugin::Com::Theke::SLNP;
use Koha::SearchEngine::Search;

use List::MoreUtils qw(any uniq);
use Scalar::Util    qw(blessed);
use Try::Tiny;

use SLNP::Exceptions;

=head1 NAME

SLNP::Commands::DatenAenderung - Class for handling DatenAenderung (PFL) commands

=head1 API

=head2 Methods

=cut

=head3 SLNPPFLDatenAenderung

Main command to be run from the server.

=cut

sub SLNPPFLDatenAenderung {
    my ( $cmd, $params ) = @_;

    my $configuration = Koha::Plugin::Com::Theke::SLNP->new->configuration;

    if ( $cmd->{'req_valid'} == 1 ) {

# strip $configuration->{pfl_number_prefix}
# when pfl_number_prefix is set to "@" the zfl server omits it on the DatenAenderung request.

        if (
            (
                   $configuration->{pfl_number_prefix} eq "@"
                && $params->{PFLNummer} =~ /^(\d*)$/
            )
            || $params->{PFLNummer} =~
            /^$configuration->{pfl_number_prefix}(\d*)$/
          )

        {
            my $illrequest_id = $1;

            my $illrequest = Koha::ILL::Requests->find($illrequest_id);

            return request_rejected( $cmd, 'SLNP_PFL_NOT_EXISTING',
                "PFL-Nummer nicht vorhanden" )
              unless ($illrequest);

            my $slnp_illbackend =
              $illrequest->load_backend("SLNP");    # this is still $illrequest

            my $args              = {};
            my $attribute_mapping = attribute_mapping();
            foreach my $attribute ( keys %{$attribute_mapping} ) {
                if ( defined $params->{$attribute}
                    && length( $params->{$attribute} ) )
                {
                    $args->{ $attribute_mapping->{$attribute} } =
                      $params->{$attribute};
                }
            }

            while ( my ( $type, $value ) = each %{$args} ) {
                my $attr = $illrequest->extended_attributes->find(
                    {
                        type => $type
                    }
                );

                if ($attr) {    # update
                    if ( $attr->value ne $value ) {
                        $attr->update( { value => $value, } );
                    }
                }
                else {          # new
                    $attr = Koha::ILL::Request::Attribute->new(
                        {
                            illrequest_id => $illrequest_id,
                            type          => $type,
                            value         => $value,
                        }
                    )->store;
                }

            }
        }
        else {
            return request_rejected( $cmd, 'SLNP_PFL_NOT_PLAUSIBLE',
                "PFL-Nummer ist nicht plausibel!" );
        }
    }
    return $cmd;
}

=head3 attribute_mapping

Simple SLNP -> Koha ILL request attribute mapping.

=cut

sub attribute_mapping {
    return {
        AufsatzAutor   => 'article_author',
        AufsatzTitel   => 'article_title',
        AusgabeOrt     => 'pickup_location_description',
        Band           => 'volume',
        Bemerkung      => 'notes',
        BenutzerNummer => 'cardnumber',
        BestellId      => 'zflorderid',
        EJahr          => 'year',
        Info           => 'info',
        Isbn           => 'isbn',
        Issn           => 'issn',
        Seitenangabe   => 'pages',
        Signatur       => 'shelfmark',
        Titel          => 'title',
        Verfasser      => 'author',
        Verlag         => 'publisher',
        Auflage        => 'issue',                         # copy case
        Heft           => 'issue',                         # loan case
        SigelGB        => 'sigel_lending_library',
        ErledFrist     => 'due_date',
    };
}

=head3 request_accepted

    request_accepted( $cmd, $pflnummer );

Helper method that makes I<$cmd> carry the right information for a successful request.

=cut

sub request_accepted {
    my ( $cmd, $pflnummer ) = @_;

    $cmd->{rsp_para}->[0] = {
        resp_pnam => 'PFLNummer',
        resp_pval => $pflnummer,
    };

    $cmd->{rsp_para}->[1] = {
        resp_pnam => 'OKMsg',
        resp_pval => 'Bestellung wird bearbeitet',
    };

    return $cmd;
}

=head3 request_rejected

    request_rejected( $cmd, $type, $text );

Helper method that makes I<$cmd> carry the right information for a rejected request.

=cut

sub request_rejected {
    my ( $cmd, $type, $text, $warn ) = @_;

    $cmd->{req_valid} = 0;
    $cmd->{err_type}  = $type;
    $cmd->{err_text}  = $text;

    $cmd->{warn} = $warn
      if $warn;

    return $cmd;
}

1;
