package SLNP::Server;

# Copyright 2018-2019 (C) LMSCLoud GmbH
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

########################################################################################################################
#                                                                                                                      #
# about SLNP                                                                                                           #
# SLNP (TM) (Simple Library Network Protocol) is a TCP network socket based protocol                                   #
# designed and introduced by the company Sisis Informationssysteme GmbH (later a part of OCLC)                         #
# for their library management system SISIS-SunRise (TM).                                                              #
# This protocol supports the bussiness processes of libraries.                                                         #
# A subset of SLNP that enables the communication required for regional an national ILL (Inter Library Loan) processes #
# has been published by Sisis Informationssysteme GmbH as basis for                                                    #
# connection of library management systems to ILL servers that use SLNP.                                               #
# Sisis Informationssysteme GmbH / OCLC owns all rights to SLNP.                                                       #
# SLNP is a registered trademark of Sisis Informationssysteme GmbH / OCLC.                                             #
#                                                                                                                      #
########################################################################################################################

use base Net::Server::Fork;

use Modern::Perl;

use utf8;
use Carp;
use Data::Dumper;
use DateTime;

# each real SLNP command is handled in an individual perl module
use SLNP::Commands::Bestellung;
use SLNP::Commands::DatenAenderung;

use SLNP::Normalizer qw();

BEGIN {
    if ( !exists( $ENV{"KOHA_CONF"} ) ) {
        croak "SLNP::Server: KOHA_CONF is not set.\n";
    }
    if ( exists( $ENV{"MEMCACHED_NAMESPACE"} ) ) {
        delete $ENV{"MEMCACHED_NAMESPACE"};
    }
    if ( exists( $ENV{"MEMCACHED_SERVERS"} ) ) {
        delete $ENV{"MEMCACHED_SERVERS"};
    }
    $|++;
}

my $SlnpErr2HttpCode = {
    SLNP_REQ_ANALYZING_ERROR => {
        'code' => 520,
        'text' => 'SlnpInternalError'
    },
    SLNP_REQ_FORMAT_ERROR => {
        'code' => 520,
        'text' => 'SlnpRequestError'
    },
    SLNP_END_COMMAND_LACKING => {
        'code' => 520,
        'text' => 'SlnpRequestError'
    },
    SLNP_CMD_NOT_IMPLEMENTED => {
        'code' => 520,
        'text' => 'SlnpLookupError'
    },
    SLNP_PARAM_VALUE_NOT_VALID => {
        'code' => 520,
        'text' => 'SlnpRequestError'
    },
    SLNP_PARAM_LEVEL_WRONG => {
        'code' => 520,
        'text' => 'SlnpRequestError'
    },
    SLNP_PARAM_GROUP_ERROR => {
        'code' => 520,
        'text' => 'SlnpRequestError'
    },
    SLNP_PARAM_UNSPECIFIED => {
        'code' => 520,
        'text' => 'SlnpRequestError'
    },
    SLNP_MAND_PARAM_LACKING => {
        'code' => 520,
        'text' => 'SlnpRequestError'
    },
    SLNP_CMD_EXECUTION_ERROR => {
        'code' => 520,
        'text' => 'SlnpExecutionError'
    },
    INTERNAL_SERVER_ERROR => {
        code => 520,
        text => 'SlnpExecutionError'
    },
    PATRON_NOT_FOUND => {
        code => 510,
        text => 'SlnpRequestError'
    },
    RECORD_NOT_FOUND => {
        code => 510,
        text => 'SlnpRequestError',
    },
    NO_AVAILABLE_ITEMS => {
        code => 510,
        text => undef,
    },
    SLNP_PFL_NOT_EXISTING => {
        'code' => 510,
        'text' => 'PFLNummerNichtVorhanden'
    },
    SLNP_PFL_NOT_PLAUSIBLE => {
        'code' => 510,
        'text' => 'PFLNummerNichtPlausibel'
    },

};

my $SLNPCmds = {
    'SLNPFLBestellung' => {
        'slnpparams' => {

            # <SpecIssue>
            'SpecIssue' => {
                'level' => 1,
                'regex' => '^\s*(.+)$',
            },

            # <Band>
            'Band' => {
                'level' => 1,
                'regex' => '^\s*(.+)$',
            },

            # <BestellTyp>
            'BsTyp' => {
                'level' => 1,
                'regex' => '^\s*(PFL|AFL)$',
                'mand'  => 1,
            },

            # <?> FIXME: need more info on the field spec. Looks like 'V' and 'C' are valid values
            'BsTyp2' => {
                'level' => 1,
                'regex' => '^\s*(.+)$',
            },

            # <BestellId des ZFLServer>
            'BestellId' => {
                'level' => 1,
                'regex' => '^\s*(\S.*?)$',
                'mand'  => 1,
            },

            # <Sigelliste der Lieferbibl.>
            'SigelListe' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Sigel der nehmenden Bibl.>
            'SigelNB' => {
                'level' => 1,
                'regex' => '^\s*(\S.*?)\s*$',
                'mand'  => 1,
            },

            # <Benutzernummer des Bestellers>
            'BenutzerNummer' => {
                'level' => 1,
                'regex' => '^\s*(\S.*?)\s*$',
                'mand'  => 1,
            },

            # <Vorname>
            'Vorname' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Nachname>
            'Nachname' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Bezeichnung>
            'Bezeichung' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Ort>
            'Ort1' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <PLZ>
            'Plz1' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Strasse>
            'Strasse1' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Adresszusatz>
            'AdressZusatz1' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Telefon>
            'Telefon1' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Email>
            'Email1' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Fax>
            'Fax1' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <TAN-Nummer>
            'TAN' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Erledigungsfrist>
            'ErledFrist' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <HBZ-Id des Mediums im SIAS-Format>
            'HBZId' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Datensatz-Id des Mediums>    (mandatory?)
            'TitelId' => {
                'level' => 1,
                'regex' => '^\s*(.*)\s*$',
            },

            # <Verfasser>
            'Verfasser' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Titel>
            'Titel' => {
                'level' => 1,
                'regex' => '^\s*(\S.*?)\s*$',
                'mand'  => 1,
            },

            # <Untertitel>
            'UnterTitel' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Reihentitel>
            'ReihenTitel' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Koerperschaft>
            'Koerperschaft' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Aufsatztitel>
            'AufsatzTitel' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <AufsatzAutor>
            'AufsatzAutor' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Verlag>
            'Verlag' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <ISBN>
            'Isbn' => {
                'level' => 1,
                'regex' => '^\s*(\S.*?)\s*$',
            },

            # <ISSN>
            'Issn' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Erscheinungsjahr>
            'EJahr' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Erscheinungsort>
            'EOrt' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Info>
            'Info' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Bandangabe>
            'Band' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Heftnr.>
            'Heft' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Auflage>
            'Auflage' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Seitenangabe>
            'Seitenangabe' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Leihverkehrsart>
            'Leihverkehrsart' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Signatur>
            'Signatur' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Bemerkung>
            'Bemerkung' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Quellenangabe>
            'Quelle' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Info zur Kostenuebernahme>
            'KostenUeb' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

# <Ausgabestelle für Abholung> (HBZ-NRW überträgt hier die Bezeichnung der Abholzweigstelle im Klartext; branchcode wäre ebenfalls möglich)
            'AusgabeOrt' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Kostenstelle>
            'Kostenstelle' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            },

            # <Max. Kosten bei Kopienbestellungen>
            'MaxKostenKopie' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
            }
        },
        'execute' => 'cmdFLBestellung',
    },

    'SLNPQuit' => {

        # special command managed internally
    },
        'SLNPPFLDatenAenderung' => {
        'slnpparams' => {

            # <call number>
            'Signatur' => {
                'level' => 1,
                'regex' => '^\s*(.+)$',
            },
            # <org code giving library >
            'SigelGB' => {
                'level' => 1,
                'regex' => '^\s*(.+)$',
            },
            # koha ill request id
            'PFLNummer' => {
                'level' => 1,
                'regex' => '^\s*(.+)\s*$',
                'mand'  => 1,
            },  
        },
        'execute' => 'cmdPFLDatenAenderung',
    },
};

# just using the standard function name 'process_request' within Net::Server::Fork
sub process_request {
    my $self  = shift;
    my $inbuf = '';
    my ( $loginrequired, $loggedin, $quitconnection ) = ( 0, 0, 0 );
    $self->log( 3, getTime() . " [SLNP::Server] New request" );

    binmode STDIN,  ":utf8";
    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";

    while ( my $line = <STDIN> ) {
        $line =~ s/\r//sg;

        $self->log( 3, getTime() . " read from STDIN:$line:" );

        $inbuf .= $line;
        if (   $inbuf =~ /^\s*SLNPEndCommand\s*/m
            || $inbuf =~ /^\s*SLNPQuit\s*/m )
        {

            $self->log( 3, getTime() . " [SLNP::Server] New SLNP command received:$inbuf:" );

            my $responsecode = '501';
            my $responsetext = 'Error while processing SLNP command';

            ( $responsecode, $responsetext ) =
              $self->evalSlnpCmd( $inbuf, $loginrequired, \$loggedin,
                \$quitconnection );

            $responsetext //= '';

            if ( $responsecode ne '200' ) {
                $self->log( 3,
                    getTime() . " [SLNP::Server]"
                      . " responsecode:$responsecode: responsetext:$responsetext:"
                );
            }
            if ($quitconnection) {
                last;
            }
            print "$responsecode $responsetext\n";

            # empty the input buffer before reading the next SLNP request
            $inbuf = '';
        }
    }
}

sub getTime {
    return DateTime->now( time_zone => C4::Context->tz() )
      ->strftime('%Y/%m/%d-%H:%M:%S');
}

sub evalSlnpCmd {
    my $self = shift;
    my ( $slnpreq, $loginrequired, $loggedin, $quit ) = @_;
    my $slnpcmd;
    my $slnpcmdname;

    $slnpcmd = eval { $self->analyzeSLNPReq($slnpreq); };
    if ($slnpcmd) {
        if ( $slnpcmd->{'req_valid'} == 1 ) {
            eval { $self->validateSLNPReq( $slnpcmd, 0 ); };
            $slnpcmdname = $slnpcmd->{'cmd_name'};
        }
        else {
            $slnpcmd->{'err_type'} = 'SLNP_REQ_FORMAT_ERROR';
            $slnpcmd->{'err_text'} =
                'Error in request, line no.:'
              . $slnpcmd->{'err_l_no'}
              . ' line:"'
              . $slnpcmd->{'err_line'} . '"';
        }
        if (
            $slnpcmd->{'req_valid'}
            && (   $loginrequired == 0
                || ( $loginrequired == 1 && $$loggedin == 1 )
                || ( $$loggedin == 0 && $slnpcmdname eq 'SLNPQuit' ) )
          )
        {

            if ( $slnpcmdname eq 'SLNPQuit' ) {
                $$quit = 1;
                $slnpcmd->{'req_valid'} = 1;
            }
            else {
                $slnpcmd =
                  eval( '$self->'
                      . $SLNPCmds->{$slnpcmdname}->{'execute'}
                      . '($slnpcmd)' );
            }
            if ( $@ ne '' ) {
                $slnpcmd->{'req_valid'} = 0;
                $slnpcmd->{'err_type'}  = 'SLNP_CMD_EXECUTION_ERROR';
                $slnpcmd->{'err_text'} =
                  "Error while executing SLNP command '$slnpcmdname':$@";
            }
        }
        elsif ( $slnpcmd->{'req_valid'} == 1 ) {
            $slnpcmd->{'req_valid'} = 0;
            $slnpcmd->{'err_type'}  = 'SLNP_NOT_LOGGED_IN';
        }
    }
    else {
        $slnpcmd->{'req_valid'} = 0;
        $slnpcmd->{'err_type'}  = 'SLNP_REQ_ANALYZING_ERROR';
        $slnpcmd->{'err_text'} =
          "Error while analyzing SLNP request :$slnpreq:";
    }

    if ( $$quit > 0 ) {
        return $slnpcmd;
    }
    return $self->genSLNPResp($slnpcmd);
}

# functions for parsing the SLNP request

sub analyzeSLNPReq {
    my $self    = shift;
    my $slnpreq = shift;
    my ( $slnpreqlineNo, @level, $lv, $cmd );
    $self->log( 3, getTime() . " [SLNP::Server] analyzeSLNPReq" );

    if (   $slnpreq =~ /^\s*SLNPEndCommand\s*/m
        || $slnpreq =~ /^\s*SLNPQuit\s*/m )
    {
        $lv                 = 0;
        $level[$lv]         = 0;
        $slnpreqlineNo      = 1;
        $cmd->{'req_valid'} = 1;

        foreach my $slnpreqline ( split( /\n/, $slnpreq ) ) {
            if ( $slnpreqline =~ /^\s*(SLNPBegin|SLNPEnd|SLNP\w+)\s*$/ ) {
                my $cmdname = $1;
                if (
                    !(
                           $cmdname eq 'SLNPBegin'
                        || $cmdname eq 'SLNPEnd'
                        || $cmdname eq 'SLNPEndCommand'
                        || $lv > 0
                    )
                  )
                {
                    $cmd->{'cmd_name'} = $cmdname;
                    $level[ ++$lv ] = 0;
                }
                elsif ( $cmdname eq 'SLNPEndCommand' ) {
                    if ( $lv != 1 ) {
                        $cmd->{'req_valid'} = 0;
                        $cmd->{'err_l_no'}  = $slnpreqlineNo;
                        $cmd->{'err_line'}  = $slnpreqline;
                        last;
                    }
                    $lv -= 1;
                }
                elsif ( $cmdname eq 'SLNPBegin' ) {
                    if ( $lv <= 0 ) {
                        $cmd->{'req_valid'} = 0;
                        $cmd->{'err_l_no'}  = $slnpreqlineNo;
                        $cmd->{'err_line'}  = $slnpreqline;
                        last;
                    }
                    my $leveloffsets = join( '_', @level[ 0 .. $lv - 1 ] );
                    $cmd->{'lvl_line'}->{$leveloffsets}->{'req_pcnt'} =
                      $cmd->{'lvl_line'}->{$leveloffsets}->{'req_pcnt'} + 1;
                    $level[$lv] += 1;
                    $level[ ++$lv ] = 0;
                }
                else {
                    if ( $lv <= 1 ) {
                        $cmd->{'req_valid'} = 0;
                        $cmd->{'err_l_no'}  = $slnpreqlineNo;
                        $cmd->{'err_line'}  = $slnpreqline;
                        last;
                    }
                    $lv--;
                }
            }
            elsif ( $slnpreqline =~ /^\s*(\w+)\s*:(.*)$/ ) {
                if ( $lv < 1 ) {
                    $cmd->{'req_valid'} = 0;
                    $cmd->{'err_l_no'}  = $slnpreqlineNo;
                    $cmd->{'err_line'}  = $slnpreqline;
                    last;
                }
                else {
                    my $leveloffsets = join( '_', @level[ 0 .. $lv - 1 ] );
                    $cmd->{'lvl_line'}->{$leveloffsets}->{'req_pcnt'} += 1
                      ; # SLNP request parameter count (within this level offset)
                    $leveloffsets .=
                      '_' . $cmd->{'lvl_line'}->{$leveloffsets}->{'req_pcnt'};
                    $cmd->{'lvl_line'}->{$leveloffsets}->{'req_pnam'} =
                      $1;    # SLNP request parameter name
                    $cmd->{'lvl_line'}->{$leveloffsets}->{'req_pval'} =
                      $2;    # SLNP request parameter value
                    $level[$lv] += 1;
                }
            }
            elsif ( $slnpreqline !~ /^\s*$/ ) {
                $cmd->{'req_valid'} = 0;
                $cmd->{'err_l_no'}  = $slnpreqlineNo;
                $cmd->{'err_line'}  = $slnpreqline;
                last;
            }
            $slnpreqlineNo += 1;
        }
    }
    else {
        $cmd->{'req_valid'} = 0;
        $cmd->{'err_type'}  = 'SLNP_END_COMMAND_LACKING';
    }
    return $cmd;
}

sub validateSLNPReq {
    my $self                        = shift;
    my $cmd                         = shift;
    my $rejectUnspecifiedParameters = shift;
    $self->log( 3,
        getTime()
          . " [SLNP::Server] validateSLNPReq"
    );

    my ( $cmdname, %slnp, $level, $leveloffsets );
    $cmdname = $cmd->{'cmd_name'};
    if ( exists( $SLNPCmds->{$cmdname} ) ) {
        %slnp = ();
        foreach $leveloffsets (
            sort sortlevels keys( %{ $cmd->{'lvl_line'} } ) )
        {
            $level = scalar( split( /_/, $leveloffsets ) ) - 1;
            if (
                ( $cmd->{'lvl_line'}->{$leveloffsets}->{'req_pcnt'} // 0 * 1 ) == 0 )
            {
                $slnp{ $cmd->{'lvl_line'}->{$leveloffsets}->{'req_pnam'} }
                  ->{$level} += 1;
            }
        }
        foreach my $param ( keys %{ $SLNPCmds->{$cmdname}->{'slnpparams'} } ) {
            if (
                   $SLNPCmds->{$cmdname}->{'slnpparams'}->{$param}->{'mand'}
                && $SLNPCmds->{$cmdname}->{'slnpparams'}->{$param}->{'mand'} =~
                /[1x]/
                && (
                    !defined( $slnp{$param} )
                    || $slnp{$param}->{
                        $SLNPCmds->{$cmdname}->{'slnpparams'}->{$param}
                          ->{'level'}
                    } <= 0
                )
              )
            {
                $cmd->{'err_type'}  = 'SLNP_MAND_PARAM_LACKING';
                $cmd->{'err_text'}  = "The mandatory SLNP parameter '$param' is lacking in request.";
                $cmd->{'req_valid'} = 0;
                return $cmd;
            }
        }

        foreach $leveloffsets (
            sort sortlevels keys( %{ $cmd->{'lvl_line'} } ) )
        {
            $level = scalar( split( /_/, $leveloffsets ) ) - 1;
            if (
                ( $cmd->{'lvl_line'}->{$leveloffsets}->{'req_pcnt'} // 0 + 0 ) == 0 )
            {
                my $req_pnam =
                  $cmd->{'lvl_line'}->{$leveloffsets}->{'req_pnam'};
                my $req_pval =
                  $cmd->{'lvl_line'}->{$leveloffsets}->{'req_pval'};
                if (
                    exists(
                        $SLNPCmds->{$cmdname}->{'slnpparams'}->{$req_pnam}
                    )
                  )
                {
                    if ( $level !=
                        $SLNPCmds->{$cmdname}->{'slnpparams'}->{$req_pnam}
                        ->{'level'} )
                    {
                        $cmd->{'req_valid'} = 0;
                        $cmd->{'err_type'}  = 'SLNP_PARAM_LEVEL_WRONG';
                        $cmd->{'err_text'} = "SLNP parameter '$req_pnam' is located in wrong level.";
                        return $cmd;
                    }
                    if ( $SLNPCmds->{$cmdname}->{'slnpparams'}->{$req_pnam}
                        ->{'regex'} )
                    {
                        my $regexChecked = 0;
                        if ( $req_pval =~ /$SLNPCmds->{$cmdname}->{'slnpparams'}->{$req_pnam}->{'regex'}/s )
                        {
                            $cmd->{'lvl_line'}->{$leveloffsets}->{'req_pval'} =
                              $1;
                            $regexChecked = 1;
                        }
                        if ( !$regexChecked ) {
                            $cmd->{'req_valid'} = 0;
                            $cmd->{'ERRPOS'}    = $leveloffsets;
                            $cmd->{'err_type'}  = 'SLNP_PARAM_VALUE_NOT_VALID';
                            $cmd->{'err_text'}  = "The value '$req_pval' is not valid for parameter '$req_pnam'.";
                            return $cmd;
                        }
                    }
                }
                else {
                    if ($rejectUnspecifiedParameters) {
                        $cmd->{'req_valid'} = 0;
                        $cmd->{'ERRPOS'}    = $leveloffsets;
                        $cmd->{'err_type'}  = 'SLNP_PARAM_UNSPECIFIED';
                        $cmd->{'err_text'}  = "SLNP parameter '$req_pnam' is not a specified for command '$cmdname'.";
                        return $cmd;
                    }
                }
            }
        }
    }
    else {
        $self->log( 3,
            getTime()
              . " SLNP::Server::validateSLNPReq Start cmd->{'cmd_name'}:$cmd->{'cmd_name'}: DOES NOT EXIST"
        );
        $cmd->{'req_valid'} = 0;
        $cmd->{'err_type'}  = 'SLNP_CMD_NOT_IMPLEMENTED';
        $cmd->{'err_text'}  = "The SLNP command '$cmdname' is not implemented.";
        return $cmd;
    }
}

sub sortlevels {
    my ( $compareLen, $ret ) = ( 0, 0 );
    my @splita = split( /_/, $a );
    my @splitb = split( /_/, $b );
    if ( $#splita < $#splitb ) {
        $compareLen = $#splita;
    }
    else {
        $compareLen = $#splitb;
    }
    for ( my $i = 0 ; $i <= $compareLen ; $i += 1 ) {
        if ( $splita[$i] > $splitb[$i] ) {
            $ret = 1;
        }
        if ( $splita[$i] < $splitb[$i] ) {
            $ret = -1;
        }
    }
    if ( $ret == 0 ) {
        if ( $#splita > $#splitb ) {
            $ret = 1;
        }
        else {
            $ret = -1;
        }
    }
    return $ret;
}

# functions for generating the SLNP response

sub genSLNPResp {
    my ( $self, $cmd ) = @_;

    my $slnpresp = '';

    $self->log( 3,
            getTime()
          . " SLNP::Server::genSLNPResp Start cmd:"
          . Dumper($cmd)
          . ' ' );

    $self->log( 1, getTime() . ' [SLNP::Server] Error running command ' . $cmd->{cmd_name} . ': ' . $cmd->{warn} )
      if $cmd->{warn};

    if ( $cmd->{'req_valid'} == 1 ) {
        if ( exists( $cmd->{'rsp_para'} ) ) {
            $slnpresp = '600 ' . $cmd->{'cmd_name'} . "\n";
            for ( my $i = 0 ; $i < scalar @{ $cmd->{'rsp_para'} } ; $i += 1 ) {
                if ( $cmd->{'rsp_para'}->[$i]->{'resp_list'} ) {
                    $self->genSLNPRespDataBlock(
                        $cmd->{'rsp_para'}->[$i]->{'resp_list'}, \$slnpresp );
                }
                else {
                    $slnpresp .= '601 '
                      . $self->escapeSLNP(
                        $cmd->{'rsp_para'}->[$i]->{'resp_pnam'} )
                      . ':'
                      . $self->escapeSLNP(
                        $cmd->{'rsp_para'}->[$i]->{'resp_pval'} )
                      . "\n";
                }
            }
            $slnpresp .= "250 SLNPEndOfData\n";
        }
        else {
            $slnpresp = '240 OK: ' . $cmd->{'cmd_name'} . " success\n";
        }
    }
    else {

        my $err_type = $cmd->{err_type};

        if ( exists( $SlnpErr2HttpCode->{$err_type} ) ) {
            $slnpresp = $self->escapeSLNP( $SlnpErr2HttpCode->{$err_type}->{code} );
            $slnpresp .= ' ' . $SlnpErr2HttpCode->{$err_type}->{text}
                if defined $SlnpErr2HttpCode->{$err_type}->{text};
        } else {
            $slnpresp = '510 SLNPEvalError: Undefined error';
        }

        if ( $cmd->{err_text} ne '' ) {
            $slnpresp .= ( defined $SlnpErr2HttpCode->{$err_type}->{text} ? ': ' : ' ' ) . $cmd->{err_text};
        }
        $slnpresp .= "\n";
    }
    $self->log( 3,
            getTime()
          . " [SLNP::Server] genSLNPResp slnpresp:"
          . $slnpresp );
    return $slnpresp;
}

sub genSLNPRespDataBlock {
    my $self     = shift;
    my $respdata = shift;
    my $slnpresp = shift;

    if ( $respdata && scalar @{$respdata} > 0 ) {
        $$slnpresp .= "604 SLNPBegin\n";
        for ( my $i = 0 ; $i < scalar @{$respdata} ; $i += 1 ) {
            if ( $respdata->[$i]->{'resp_list'} ) {
                $self->genSLNPRespDataBlock( $respdata->[$i]->{'resp_list'},
                    $slnpresp );
            }
            else {
                $$slnpresp .= '603 '
                  . $self->escapeSLNP( $respdata->[$i]->{'resp_pnam'} ) . ':'
                  . $self->escapeSLNP( $respdata->[$i]->{'resp_pval'} ) . "\n";
            }
        }
        $$slnpresp .= "605 SLNPEnd\n";
    }
}

sub escapeSLNP {
    my $self = shift;
    my ($s) = @_;

    $s =~ s/\n/\\n/g;
    $s =~ s/\\/\\\\/g;
    return $s;
}

sub unescapeSLNP {
    my $self = shift;
    my ($s) = @_;

    $s =~ s/\\n/"\n"/eg;
    $s =~ s/\\\\/'\\'/eg;
    return $s;
}

# functions for executing the parsed SLNP commands

sub readSLNPParam {
    my $self   = shift;
    my $cmd    = shift;
    my $lv     = shift;
    my @params = @_;
    $self->log( 3,
        getTime() . " [SLNP::Server] readSLNPParam Start level:$lv:" );
    my ( $reqParamVals, $oldbaselevel, $leveloffsets );

    $reqParamVals = undef;
    $oldbaselevel = '';

    if ( scalar @params ) {
        foreach $leveloffsets (
            sort sortlevels keys( %{ $cmd->{'lvl_line'} } ) )
        {
            my $l = scalar( split( /_/, $leveloffsets ) ) - 1;
            if (   $l == $lv
                && $cmd->{'lvl_line'}->{$leveloffsets}->{'req_pcnt'} // 0 + 0 == 0 )
            {
                foreach my $param ( 0 .. $#params ) {

                    my $value = SLNP::Normalizer->new(
                        {
                            string => $self->escapeSLNP(
                                $cmd->{'lvl_line'}->{$leveloffsets}
                                  ->{'req_pval'}
                            )
                        }
                    )->trim->get_string;

                    if ( $params[$param] eq
                        $cmd->{'lvl_line'}->{$leveloffsets}->{'req_pnam'} )
                    {
                        my $baselevel = join( "_",
                            ( split( /_/, $leveloffsets ) )[ 0 .. ( $l - 1 ) ]
                        );
                        if ( $baselevel eq $oldbaselevel ) {
                            if ( $reqParamVals->[$#$reqParamVals]->[$param] eq
                                '' )
                            {
                                $reqParamVals->[$#$reqParamVals]->[$param] = $value;
                            }
                            else {
                                $reqParamVals->[$#$reqParamVals]->[$param] .=
                                  "\n"
                                  . $value;
                            }
                        }
                        else {
                            $reqParamVals->[ $#$reqParamVals + 1 ]->[$param] = $value;
                            $oldbaselevel = $baselevel;
                        }
                    }
                }
            }
        }
    }

    return $reqParamVals;
}

sub cmdPFLDatenAenderung {
# fix
  my ( $self, $slnpcmd ) = @_;

    $self->log(
        3,
        getTime() . "[SLNP::Server][DatenAenderung] " . $slnpcmd->{'cmd_name'} . ":"
    );

    my ( $cmd, $res, $conn, $request ) = undef;

    my $params = undef;
    my @fields = (
        'PFLNummer',
        'SigelGB',
        'Signatur',
    );

    foreach my $field (@fields) {
        my $param = $self->readSLNPParam( $slnpcmd, 1, $field );
        $params->{$field} = $param->[0]->[0] if $param;
    }

    $self->log( 3, getTime() . " [SLNP::Server] > params:" . Dumper($params) );

    $res = SLNP::Commands::DatenAenderung::SLNPPFLDatenAenderung( $slnpcmd, $params );

    $self->log(
        3,
        getTime()
            . " [SLNP::Server] SLNPFLBestellung has returned, res->{'cmd_name'}:"
            . $res->{'cmd_name'}
            . ":, res->{'req_valid'}:"
            . $res->{'req_valid'}
    );

    return $slnpcmd;
}


sub cmdFLBestellung {
    my ( $self, $slnpcmd ) = @_;

    $self->log(
        3,
        getTime() . "[SLNP::Server][Bestellung] " . $slnpcmd->{'cmd_name'} . ":"
    );

    my ( $cmd, $res, $conn, $request ) = undef;

    my $params = undef;

    my @fields = (
        'Auflage',
        'AufsatzAutor',
        'AufsatzTitel',
        'AusgabeOrt',
        'Band',
        'Bemerkung',
        'BenutzerNummer',
        'BestellId',
        'BsTyp',
        'BsTyp2',
        'EJahr',
        'ExternReferenz',
        'Heft',
        'Info',
        'Isbn',
        'Issn',
        'Seitenangabe',
        'SigelListe',
        'SigelNB',
        'Signatur',
        'SpecIssue',
        'Titel',
        'TitelId',
        'Verfasser',
        'Verlag',
    );

    foreach my $field (@fields) {
        my $param = $self->readSLNPParam( $slnpcmd, 1, $field );
        $params->{$field} = $param->[0]->[0] if $param;
    }

    $self->log( 3, getTime() . " [SLNP::Server] > params:" . Dumper($params) );

    $res = SLNP::Commands::Bestellung::SLNPFLBestellung( $slnpcmd, $params );

    $self->log(
        3,
        getTime()
            . " [SLNP::Server] SLNPFLBestellung has returned, res->{'cmd_name'}:"
            . $res->{'cmd_name'}
            . ":, res->{'req_valid'}:"
            . $res->{'req_valid'}
    );

    return $slnpcmd;
}

1;
