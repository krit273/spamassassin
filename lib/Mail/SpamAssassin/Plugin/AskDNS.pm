# <@LICENSE>
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to you under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at:
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# </@LICENSE>

=head1 NAME

AskDNS - form a DNS query using tag values, and look up the DNSxL lists

=head1 SYNOPSIS

  loadplugin  Mail::SpamAssassin::Plugin::AskDNS
  askdns DKIMDOMAIN_IN_DWL _DKIMDOMAIN_._vouch.dwl.spamhaus.org TXT /\ball\b/

=head1 DESCRIPTION

Using a DNS query template as specified in a parameter of the askdns rule,
the plugin replaces tag names as found in the template with their values as
soon as they become available, and launches DNS queries. When DNS responses
trickle in, filters them according the requested DNS resource record type
and optional subrule filtering expression, yielding a rule hit if a response
meets filtering conditions.

=head1 USER SETTINGS

=over 4

=item rbl_timeout t [t_min] [zone]		(default: 15 3)

The rbl_timeout setting is common to all DNS querying rules. It can
specify a DNS query timeout globally, or individually for each zone.
See the C<Mail::SpamAssassin::Conf> POD for details on C<rbl_timeout>.

=back

=head1 RULE DEFINITIONS

=over 4

=item askdns NAME_OF_RULE query_template [rr_type [subqueryfilter]]

A query template is a string which will be expanded to produce a domain name
to be used in a DNS query. The template may include SpamAssassin tag names,
which will be replaced with their values to form the final query domain.
The final query domain must adhere to rules governing DNS domains, i.e. must
consist of fields each up to 63 characters long, delimited by dots. There
may be a trailing dot at the end, but it is redundant / carries no semantics,
because SpamAssassin uses a Net::DSN::Resolver::send method for querying
DNS, which ignores any 'search' or 'domain' DNS resolver options.
Domain names in DNS queries are case-insensitive.

A tag name is a string of capital letters, preceded and followed by an
underscore character. This syntax mirrors the add_header setting, except that
tags cannot have parameters in parenthesis when used in askdns templates.
Tag names may appear anywhere in the template - each queried DNS zone
prescribes how a query should be formed.

A query template may contain any number of tag names including none,
although in the most common anticipated scenario exactly one tag name would
appear in each askdns rule. Specified tag names are considered dependencies.
Askdns rules with dependencies on the same set of tags are grouped, and all
queries in a group are launched as soon as all their dependencies are met,
i.e. when the last of the awaited tag values becomes available by a call
to set_tag() from some other plugin or elsewhere in the SpamAssassin code.

Launched queries from all askdns rules are grouped too according to a pair
of: RR type and expanded query domain name. Even if there are multiple rules
producing the same type/domain pair, only one DNS query is launched, and
a reply to such query contributes to all the constituent rules.

A tag may produce none, one or multiple values. Askdns rules waiting for
a tag which never receives its value never result in a DNS query. Tags which
produce multiple values will result in multiple queries launched, each with
an expanded template using one of the tag values. An example is a DKIMDOMAIN
tag which yields a list of signing domains, one for each valid signature in
a message signed by more than one domain.

When more than one tag name appears in a template, each potentially resulting
in multiple values, a Cartesian product is formed, and each tuple results in
a launch of one DNS query (duplicates excluded). For example, a query template
_A_._B_.example.com where tag A is a list (11,22) and B is (xx,yy,zz),
will result in queries: 11.xx.example.com, 22.xx.example.com,
11.yy.example.com, 22.yy.example.com, 11.zz.example.com, 22.zz.example.com .

The parameter following the query template is a DNS resource record (RR)
type. A DNS result may bring resource records of multiple types, but only
those resource records matching the type specified in a rule are considered,
returned resource records with non-matching types are ignored for this rule.
Currently the RR type parameter also determines the DNS query types (not
just the filter for the result), although in future similar queries could
be combined, launching a query of type 'ANY'. Currently allowed RR types
are: A, AAAA, MX, TXT, PTR, NS, SOA, CNAME, HINFO, MINFO, WKS, SRV, SPF.

The last optional parameter of a rule is filtering expression, a.k.a. a
subrule. Its function is much like the subrule in URIDNSBL plugin rules
(like in the uridnssub rules), or in the check_rbl eval rules. The main
difference is that with askdns rules there is no need to manually group
rules according to their queried zone, as the grouping is automatic and
duplicate queries are implicitly eliminated.

The subrule filtering parameter can be: a plain string, a regular expression,
a single numerical value. or a pair of numerical values. Absence of the
filtering parameter implies no filtering, i.e. any positive DNS response
of the requested RR type will result in a rule hit, regardless of the RR
value returned with the response.

When a plain string is used as a filter, it must match the response exactly.
Typical use is an exact text string for TXT queries.

A regular expression follows a familiar perl syntax like /.../ or m{...}
optionally followed by regexp flags (such as 'i' for case-insensitivity).
If a DNS response matches the requested RR type and the regular expression,
the rule hits. Typical use: /^127\.0\.0\.\d+$/ or m{\bdial up\b}i .

A single numerical value can be a decimal number, or a hexadecimal number
prefixed by 0x. Such numeric filtering expression is typically used with
RR type-A DNS queries. The returned value (IP address) is masked with the
specified filtering value, and the rule hits if the result is nonzero:
(r & n) != 0 .  An example: 0x10 .

A pair of numerical values (each a decimal, hexadecimal or quad-dotted)
delimited by a '-' specifies an IP address range, and a pair of values
delimited by a '/' specifies an IP address followed by a bitmask. Again,
this type of filtering expression is primarily intended with RR type-A
DNS queries. The rule hits if the returned IP address falls within the
specified range: (r >= n1 && r <= n2), or masked with a bitmask matches
the specified value: (r & m) == (n & m) .  As a shorthand notation,
a single quad-dotted value is equivalent to a n/32 form, i.e. it must
match the returned value exactly with all its bits.

Some typical examples of a numeric filtering parameter are: 127.0.1.2,
127.0.1.20-127.0.1.39, 127.0.1.0/255.255.255.0, 0.0.0.16/0.0.0.16,
0x10/0x10, 16, 0x10 .

=back

=cut

package Mail::SpamAssassin::Plugin::AskDNS;

use strict;
use warnings;
use re 'taint';

use Mail::SpamAssassin::Plugin;
use Mail::SpamAssassin::Util;
use Mail::SpamAssassin::Logger;

use vars qw(@ISA);
@ISA = qw(Mail::SpamAssassin::Plugin);

sub new {
  my($class,$sa_main) = @_;

  $class = ref($class) || $class;
  my $self = $class->SUPER::new($sa_main);
  bless($self, $class);

  $self->set_config($sa_main->{conf});

  return $self;
}

# ---------------------------------------------------------------------------

# Accepts argument as a regular expression (including its m() operator or
# equivalent perl syntaxes), or in one of the following forms: m, n1-n2,
# or n/m, where n,n1,n2,m can be any of: decimal digits, 0x followed by
# up to 8 hexadecimal digits, or an IPv4 address in quad-dotted notation.
# The argument is checked for syntax, undef is returned on syntax errors.
# A string that looks like a regular expression is converted to a compiled
# Regexp object and returned as a result. Otherwise, numeric components of
# the remaining three forms are converted as follows: hex or decimal numeric
# strings are converted to a number and a quad-dot is converted to a number,
# then components are reassembled into a string delimited by '-' or '/'.
# As a special backward compatibility measure, a single quad-dot (with no
# second number) is converted into n-n, to distinguish it from a traditional
# mask-only form.
#
# In practice, arguments like the following are anticipated:
#   127.0.1.2  (same as 127.0.1.2-127.0.1.2 or 127.0.1.2/255.255.255.255)
#   127.0.1.20-127.0.1.39  (= 0x7f000114-0x7f000127 or 2130706708-2130706727)
#   0.0.0.16/0.0.0.16  (same as 0x10/0x10 or 16/0x10 or 16/16)
#   16  (traditional style mask-only, same as 0x10)
#
sub parse_and_canonicalize_subtest {
  my($subtest) = @_;
  my $result;

  local($1,$2,$3);
  if ($subtest =~ m{^ / (.+) / ([msixo]*) \z}xs) {
    $result = $2 ne '' ? qr{(?$2)$1} : qr{$1};
  } elsif ($subtest =~ m{^ m \s* \( (.+) \) ([msixo]*) \z}xs) {
    $result = $2 ne '' ? qr{(?$2)$1} : qr{$1};
  } elsif ($subtest =~ m{^ m \s* \[ (.+) \] ([msixo]*) \z}xs) {
    $result = $2 ne '' ? qr{(?$2)$1} : qr{$1};
  } elsif ($subtest =~ m{^ m \s* \{ (.+) \} ([msixo]*) \z}xs) {
    $result = $2 ne '' ? qr{(?$2)$1} : qr{$1};
  } elsif ($subtest =~ m{^ m \s*  < (.+)  > ([msixo]*) \z}xs) {
    $result = $2 ne '' ? qr{(?$2)$1} : qr{$1};
  } elsif ($subtest =~ m{^ m \s* (\S) (.+) \1 ([msixo]*) \z}xs) {
    $result = $2 ne '' ? qr{(?$2)$1} : qr{$1};
  } elsif ($subtest =~ m{^ ([^/-]+) (?: ([/-]) (.+) )? \z}xs) {
    my($n1,$delim,$n2) = ($1,$2,$3);
    my $any_quad_dot;
    for ($n1,$n2) {
      if (!defined $_) {
        # ok, $n2 may not exist
      } elsif (/^\d{1,10}\z/) {
        $_ = 0 + $_;   # decimal string -> number
      } elsif (/^0x[0-9a-zA-Z]{1,8}\z/) {
        $_ = hex($_);  # hex string -> number
      } elsif (/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\z/) {
        $_ = Mail::SpamAssassin::Util::my_inet_aton($_);  # quad-dot -> number
        $any_quad_dot = 1;
      } else {
        return undef;
      }
    }
    $result = defined $n2 ? $n1.$delim.$n2
            : $any_quad_dot ? $n1.'-'.$n1 : "$n1";
  }
  return $result;
}

sub set_config {
  my($self, $conf) = @_;
  my @cmds;

  push(@cmds, {
    setting => 'askdns',
    is_priv => 1,
    type => $Mail::SpamAssassin::Conf::CONF_TYPE_HASH_KEY_VALUE,
    code => sub {
      my($self, $key, $value, $line) = @_;
      local($1,$2,$3,$4);
      if (!defined $value || $value =~ /^$/) {
        return $Mail::SpamAssassin::Conf::MISSING_REQUIRED_VALUE;
      } elsif ($value !~ /^ (\S+) \s+ (\S+)
                            (?: \s+ (A|AAAA|MX|TXT|PTR|NS|SOA|CNAME|
                                     HINFO|MINFO|WKS|SRV|SPF)
                                (?: \s+ (.*?) )?  )? \s* $/xs) {
        return $Mail::SpamAssassin::Conf::INVALID_VALUE;
      } else {
        my($rulename,$query_template,$query_type,$subtest) = ($1,$2,$3,$4);
        $query_type = 'A' if !defined $query_type;
        $query_type = uc $query_type;
        $subtest = '' if !defined $subtest;
        if ($subtest ne '') {
          $subtest = parse_and_canonicalize_subtest($subtest);
          defined $subtest or return $Mail::SpamAssassin::Conf::INVALID_VALUE;
        }
        # collect tag names as used in each query template
        my @tags = $query_template =~ /_([A-Z][A-Z0-9]*)_/g;
        my %seen; @tags = grep(!$seen{$_}++, @tags);  # filter out duplicates

        # group rules by tag names used in them (to be used as a hash key)
        my $depends_on_tags = !@tags ? '' : join(',',@tags);

        # subgroup rules by a DNS RR type and a nonexpanded query template
        my $query_template_key = $query_type . ':' . $query_template;

        $self->{askdns}{$depends_on_tags}{$query_template_key} ||=
          { query => $query_template, type => $query_type, rules => {} };
        $self->{askdns}{$depends_on_tags}{$query_template_key}{rules}{$rulename}
          = $subtest;
      # dbg("askdns: rule: %s, config dep: %s, domkey: %s, subtest: %s",
      #     $rulename, $depends_on_tags, $query_template_key, $subtest);

        # just define the test so that scores and lint works
        $self->{parser}->add_test($rulename, undef,
                                  $Mail::SpamAssassin::Conf::TYPE_EMPTY_TESTS);
      }
    }
  });

  $conf->{parser}->register_commands(\@cmds);
}

# run as early as possible, launching DNS queries as soon as their
# dependencies are fulfilled
#
sub extract_metadata {
  my($self, $opts) = @_;
  my $pms = $opts->{permsgstatus};
  my $conf = $pms->{conf};

  return if !$pms->is_dns_available;
  $pms->{askdns_map_dnskey_to_rules} = {};
  $pms->{askdns_dnskey_to_response} = {};

  # walk through all collected askdns rules, obtain tag values whenever
  # they may become available, and launch DNS queries right after
  #
  for my $depends_on_tags (keys %{$conf->{askdns}}) {
    my @tags;
    @tags = split(/,/, $depends_on_tags)  if $depends_on_tags ne '';
    if (!@tags) {
      # no dependencies on tags, just call directly
      $self->launch_queries($pms,$depends_on_tags);
    } else {
      # enqueue callback for tags needed
      $pms->action_depends_on_tags(@tags == 1 ? $tags[0] : \@tags,
              sub { my($pms,@args) = @_;
                    $self->launch_queries($pms,$depends_on_tags) }
      );
    }
  }
}

# generate DNS queries - called for each set of rules
# when their tag dependencies are met
#
sub launch_queries {
  my($self, $pms, $depends_on_tags) = @_;
  my $conf = $pms->{conf};

  my %tags;
  # obtain tag/value pairs of tags we depend upon in this set of rules
  if ($depends_on_tags ne '') {
    %tags = map( ($_,$pms->get_tag($_)), split(/,/,$depends_on_tags) );
  }
  dbg("askdns: preparing queries which depend on tags: %s",
      join(', ', map($_.' => '.$tags{$_}, keys %tags)));

  # replace tag names in a query template with actual tag values
  # and launch DNS queries
  while ( my($query_template_key, $struct) =
            each %{$conf->{askdns}{$depends_on_tags}} ) {
    my($query_template, $query_type, $rules) = @$struct{qw(query type rules)};

    my @rulenames = keys %$rules;
    if (grep($conf->{scores}->{$_}, @rulenames)) {
      dbg("askdns: query template %s, type %s, rules: %s",
          $query_template, $query_type, join(', ', @rulenames));
    } else {
      dbg("askdns: query template %s, type %s, all rules disabled: %s",
          $query_template, $query_type, join(', ', @rulenames));
      next;
    }

    local $1;
    # collect all tag names from a template, each may occur more than once
    my @templ_tags = $query_template =~ /_([A-Z][A-Z0-9]*)_/gs;

    # filter out duplicate tag names, and tags with undefined or empty value
    my %seen;
    @templ_tags = grep(!$seen{$_}++ && defined $tags{$_} && $tags{$_} ne '',
                       @templ_tags);

    my %templ_vals;  # values that each tag takes
    for my $t (@templ_tags) {
      my %seen;
      # a tag value may be a space-separated list,
      # store it as an arrayref, removing duplicate values
      $templ_vals{$t} = [ grep(!$seen{$_}++, split(' ',$tags{$t})) ];
    }

    # count through all tag values
    my @digit = (0) x @templ_tags;  # counting accumulator
OUTER:
    for (;;) {
      my %current_tag_val;  # maps a tag name to its current iteration value
      for my $j (0 .. $#templ_tags) {
        my $t = $templ_tags[$j];
        $current_tag_val{$t} = $templ_vals{$t}[$digit[$j]];
      }
      my $query_domain = $query_template;
      $query_domain =~ s{_([A-Z][A-Z0-9]*)_}{$current_tag_val{$1}}g;

      # the $dnskey identifies this query in AsyncLoop's pending_lookups
      my $dnskey = join(':', 'askdns', $query_type, $query_domain);
      dbg("askdns: expanded query %s, dns key %s", $query_domain, $dnskey);

      if ($pms->{async}->get_lookup($dnskey)) {  # already underway?
        warn "askdns: such lookup has already been issued: ".$dnskey;
      } else {
        if (!exists $pms->{askdns_map_dnskey_to_rules}{$dnskey}) {
          $pms->{askdns_map_dnskey_to_rules}{$dnskey} =
             [ [$query_type, $rules] ];
        } else {
          push(@{$pms->{askdns_map_dnskey_to_rules}{$dnskey}},
               [$query_type, $rules] );
        }
        if (exists $pms->{askdns_dnskey_to_response}{$dnskey}) {
          # answer already available by some earlier query, or query underway
          my $packet = $pms->{askdns_dnskey_to_response}{$dnskey};
          if (!defined $packet) {
            dbg("askdns: dns query %s already launched by some previous query",
                $dnskey);
          } else {
            dbg("askdns: dns answer from some earlier query already available");
            $self->process_response_packet($pms, $packet, $dnskey,
                                           $query_type, $query_domain);
          }
        } else {
          # lauch a new DNS query for $query_type and $query_domain
          $pms->{askdns_dnskey_to_response}{$dnskey} = undef;  # exists, undef
          my $ent = $self->start_lookup(
                  $pms, $query_type, $query_domain,
                  $self->res_bgsend($pms, $query_domain, $query_type, $dnskey),
                  $dnskey);
          # these rules are now underway;  unless the rule hits, these will
          # not be considered "finished" until harvest_dnsbl_queries() completes
          $pms->register_async_rule_start($dnskey);
        }
      }

      last  if !@templ_tags;
      # increment accumulator, little-endian
      for (my $j = 0;  ; $j++) {
        last  if ++$digit[$j] <= $#{$templ_vals{$templ_tags[$j]}};
        $digit[$j] = 0;  # and carry
        last OUTER  if $j >= $#templ_tags;
      }
    }
  }
}

sub process_response_packet {
  my($self, $pms, $packet, $dnskey, $query_type, $query_domain) = @_;
  my $conf = $pms->{conf};

  # map a dnskey back to info on queries which caused this DNS lookup
  my $queries_ref = $pms->{askdns_map_dnskey_to_rules}{$dnskey};

  my %rulenames_hit;
  my @answer;
  @answer = $packet->answer  if $packet;
  for my $rr (@answer) {
    my $rr_type = $rr->type;
    $rr_type = '' if !defined $rr_type;
    $rr_type = uc $rr_type;
    my $rr_rdatastr;
    my $rdatanum;
    if ($rr_type eq 'TXT' || $rr_type eq 'SPF') {
      # RFC 5518: If the RDATA in the TXT record contains multiple
      # character-strings (as defined in Section 3.3 of [RFC1035]),
      # the code handling that reply from DNS MUST assemble all of these
      # marshaled text blocks into a single one before any syntactical
      # verification takes place.
      # The same goes for RFC 4408 (SPF), RFC 4871 (DKIM), RFC 5617 (ADSP) ...
      $rr_rdatastr = join('', $rr->char_str_list);  # as per RFC 5518
    } else {
      $rr_rdatastr = $rr->rdatastr;
      if ($rr_type eq 'A' &&
          $rr_rdatastr =~ m/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\z/) {
        $rdatanum = Mail::SpamAssassin::Util::my_inet_aton($rr_rdatastr);
      }
    }
    # decode DNS presentation format as returned by Net::DNS
    $rr_rdatastr =~ s/\\([0-9]{3}|.)/length($1)==1 ? $1 : chr($1)/gse;
  # dbg("askdns: received rr type %s, data: %s", $rr_type, $rr_rdatastr);

    my $j = 0;
    for my $q_tuple (!ref $queries_ref ? () : @$queries_ref) {
      next  if !$q_tuple;

      my($query_type, $rules) = @$q_tuple;
      next  if $rr_type ne $query_type;
      $pms->{askdns_map_dnskey_to_rules}{$dnskey}[$j++] = undef; # mark it done

      local($1,$2,$3);
      while (my($rulename,$subtest) = each %$rules) {
        my $match;
        if (!defined $subtest || $subtest eq '') {
          $match = 1;  # any response of the requested RR type matches
        } elsif (ref $subtest eq 'Regexp') {
          $match = 1  if $rr_rdatastr =~ $subtest;
        } elsif ($rr_rdatastr eq $subtest) {
          $match = 1;
        } elsif (defined $rdatanum &&
                 $subtest =~ m{^ (\d+) (?: ([/-]) (\d+) )? \z}x) {
          my($n1,$delim,$n2) = ($1,$2,$3);
          $match =
            !defined $n2  ? $rdatanum & $n1                       # mask only
          : $delim eq '-' ? $rdatanum >= $n1 && $rdatanum <= $n2  # range
          : $delim eq '/' ? ($rdatanum & $n2) == ($n1 & $n2)      # value/mask
          : 0;  
        }
        if ($match) {
          $self->askdns_hit($pms,$query_domain,$rr_type,$rr_rdatastr,$rulename);
          $rulenames_hit{$rulename} = 1;
        }
      }
    }
  }
  # these rules have completed (since they got at least 1 hit)
  $pms->register_async_rule_finish($_)  for keys %rulenames_hit;
}

sub askdns_hit {
  my($self, $pms, $query_domain, $rr_type, $rr_rdatastr, $rulename) = @_;

  dbg('askdns: domain "%s" listed (%s): %s',
      $query_domain, $rulename, $rr_rdatastr);

  # only the first hit will show in the test log report, even if
  # an answer section matches more than once - got_hit() handles this
  $pms->clear_test_state;
  $pms->test_log(sprintf("%s %s:%s", $query_domain,$rr_type,$rr_rdatastr));
  $pms->got_hit($rulename, 'ASKDNS: ', ruletype => 'askdns');  # score=>$score
}

sub start_lookup {
  my($self, $pms, $query_type, $query_domain, $id, $dnskey) = @_;

  my $ent = {
    key => $dnskey,
    domain => $query_domain,  # used for logging and reporting
    zone => $query_domain,    # serves to fetch per-zone settings
    type => 'ASKDNS-' . $query_type,
    id => $id,
    completed_callback => sub {
      my $ent = shift;
      my $packet = $ent->{response_packet};
      if (defined $packet) {  # not aborted or empty
        my $dnskey = $ent->{key};
        # save the response, in case a later generated query would want
        # to make the same lookup
        $pms->{askdns_dnskey_to_response}{$dnskey} = $packet;
        $self->process_response_packet($pms, $packet, $dnskey,
                                       $query_type, $query_domain);
      }
    }
  };
  $pms->{async}->start_lookup($ent, $pms->{master_deadline});
  return $ent;
}

sub res_bgsend {
  my($self, $pms, $query_domain, $query_type, $dnskey) = @_;

  return $self->{main}->{resolver}->bgsend($query_domain, $query_type, undef,
    sub { my($pkt, $id, $timestamp) = @_;
          $pms->{async}->set_response_packet($id, $pkt, $dnskey, $timestamp);
        });
}

1;
