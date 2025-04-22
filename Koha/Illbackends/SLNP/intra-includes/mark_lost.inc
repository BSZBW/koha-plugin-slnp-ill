[% USE raw %]
[% USE Asset %]
[% SET footerjs = 1 %]

[% USE Koha %]
[% USE AuthorisedValues %]
[% USE ItemTypes %]
[% USE KohaDates %]
[% USE Price %]

[% IF whole.value.item_not_lost %]
    <div class="dialog message">[% whole.strings.item_not_lost | html %].</div>

    <form id="SLNP_mark_lost" name="SLNP_mark_lost" method="POST" action=[% here %]>

        <fieldset class="action">
            <input type="hidden" name="illrequest_id" id="illrequest_id" value="[% whole.illrequest_id | html %]" />
            <input type="hidden" name="backend" id="backend" value="[% request.backend | html %]" />
            <input type="hidden" name="method" id="method" value="mark_lost" />
            <input type="hidden" name="stage" id="stage" value="commit" />
            <input type="hidden" name="itemnumber" id="itemnumber" value="[% whole.value.other.itemnumber | html %]" />
            <input type="hidden" name="op" id="op" value="cud-mark-lost" />

            <a class="cancel" id="cancelbutton" name="cancelbutton" href="/cgi-bin/koha/ill/ill-requests.pl?method=illview&amp;illrequest_id=[% request.illrequest_id | uri %]">[% whole.strings.cancel | html %]</a>
        </fieldset>
    </form>
[% ELSE %]

[% IF whole.stage == 'init' %]
  <h2>[% whole.strings.title | html %] ([% request.orderid | html %])</h2>

  <p>[% whole.strings.message | html %]</p>

  <form id="SLNP_mark_lost" name="SLNP_mark_lost" method="POST" action=[% here %]>

    <fieldset class="rows">
    <legend>[% whole.strings.item | html %]</legend>
      <ol>
        <li>
          <label for="item_callnumber">[% whole.strings.item_callnumber | html %]:</label>
          <input type="text" size="50" name="item_callnumber" id="item_callnumber" value="[% whole.value.item.itemcallnumber | html %]" disabled="disabled"/>
        </li>

        <li>
          <label for="item_number_of_parts">[% whole.strings.item_num_parts | html %]:</label>
          <input type="text" size="50" name="item_number_of_parts" id="item_number_of_parts" value="[% whole.value.item.materials | html %]" disabled="disabled"/>
        </li>

        <li>
          <label for="item_internal_note">[% whole.strings.item_internal_note | html %]:</label>
          <input type="text" size="50" name="item_internal_note" id="item_internal_note" value="[% whole.value.item.itemnotes_nonpublic | html %]" disabled="disabled"/>
        </li>

        <li>
          <label for="due_date">[% whole.strings.item_due_date | html %]:</label>
          <input type="text" class="datepicker" name="due_date" id="due_date" size="10" maxlength="10" value="[% whole.value.due_date | $KohaDates %]" disabled="disabled"/>
          <span class="hint">[% INCLUDE 'date-format.inc' %]</span>
        </li>

      </ol>
    </fieldset>

    <fieldset class="rows">
    <legend>[% whole.strings.patron | html %]</legend>
      <ol>
        <li>
          <label for="the_patron">[% whole.strings.patron_requester | html %]:</label>
          <div name="the_patron" id="the_patron">
            <a target="_blank" href="/cgi-bin/koha/members/moremember.pl?borrowernumber=[% whole.value.patron.borrowernumber | uri %]">
            [% whole.value.patron.firstname | html %] [% whole.value.patron.surname | html %] ([% whole.value.patron.cardnumber | html %])</a>
          </div>
        </li>
      </ol>
    </fieldset>

    <fieldset class="rows">
        <legend>[% whole.strings.lending_library_title | html %]</legend>
        <ol>
            <li>
            [% IF whole.value.mandatory_lending_library %]
                <label class="required" for="lending_library">[% whole.strings.lending_library_name | html %]:</label>
                <select name="lending_library" id="lending_library" required="required" class="select2" style="width: 45%" data-tags="true">
            [% ELSE %]
                <label for="lending_library">[% whole.strings.lending_library_name | html %]:</label>
                <select name="lending_library" id="lending_library" class="select2" style="width: 45%" data-tags="true">
            [% END %]
                    <option value="">&nbsp;</option>
            [% FOREACH library IN whole.value.lending_libraries %]
                [% SET can_be_notified = library.first_valid_email_address ? 1 : 0 %]
                [% IF whole.value.selected_lending_library_id and whole.value.selected_lending_library_id == library.id %]
                    <option value="[% library.borrowernumber | html %]" selected="selected" data-can-be-notified="[% can_be_notified | html %]">[% library.surname | html %][% IF library.othernames %] ([% library.othernames | html %])[% END %]</option>
                [% ELSE %]
                    <option value="[% library.borrowernumber | html %]" data-can-be-notified="[% can_be_notified | html %]">[% library.surname | html %][% IF library.othernames %] ([% library.othernames | html %])[% END %]</option>
                [% END %]
            [% END %]
                </select>
            </li>

            <li>
                <label for="notify_lending_library">[% whole.strings.notify_lending_library | html %]:</label>
            [% IF !whole.value.can_be_notified %]
                <input type="checkbox" id="notify_lending_library" name="notify_lending_library" disabled="disabled" />
            [% ELSE %]
                <input type="checkbox" id="notify_lending_library" name="notify_lending_library" />
            [% END %]
            </li>
        </ol>
    </fieldset>

    <fieldset class="action">
      <input type="hidden" name="illrequest_id" id="illrequest_id" value="[% whole.illrequest_id | html %]" />
      <input type="hidden" name="backend" id="backend" value="[% request.backend | html %]" />
      <input type="hidden" name="method" id="method" value="mark_lost" />
      <input type="hidden" name="stage" id="stage" value="commit" />
      <input type="hidden" name="itemnumber" id="itemnumber" value="[% whole.value.other.itemnumber | html %]" />
      <input type="hidden" name="op" id="op" value="cud-mark-lost" />

      <button type="submit" class="btn btn-default approve">
        <i class="fa fa-check"></i> [% whole.strings.mark_lost | html %]
      </button>

      <button type="submit" class="btn btn-default openWin" data-url="/api/v1/contrib/slnp/ill_requests/[% whole.illrequest_id | uri %]/print_slips/ILL_PARTNER_LOST" data-prevent-default="yes">
        <i class="fa fa-print"></i> [% whole.strings.mark_lost_and_print | html %]
      </button>

      <a class="cancel" id="cancelbutton" name="cancelbutton" href="/cgi-bin/koha/ill/ill-requests.pl?method=illview&amp;illrequest_id=[% request.illrequest_id | uri %]">[% whole.strings.cancel | html %]</a>

    </fieldset>
  </form>

[% ELSE %]
  <p>[% whole.strings.unknown_stage | html %]: '[% whole.stage %]'</p>
[% END %]

<script>
    document.addEventListener('DOMContentLoaded', function() {

        function Dopop(link) {
            var newin = window.open(link, 'popup', 'width=600,height=400,resizable=1,toolbar=0,scrollbars=1,top');
        }

        $('.openWin').on("click",function(e){
            Dopop( $(this).data("url") );

            if ( $(this).data("prevent-default" === 'yes' ) ) {
                e.preventDefault();
            }
        });

        toggle_notify_checkbox();

        $("#lending_library").on("select2:select", function(e){toggle_notify_checkbox(e);});

        function toggle_notify_checkbox(e) {
            var can_be_notified = $("#lending_library").select2().find(":selected").data("can-be-notified");

            if ( can_be_notified === 1 ) {
                $("#notify_lending_library").removeAttr("disabled");
            }
            else {
                $("#notify_lending_library")
                    .attr( "disabled", true )
                    .prop( "checked", false );
            }
        }
    });
</script>

[% END %]