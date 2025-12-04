# Koha Interlibrary Loans SLNP backend

## Synopsis

This project involves three different pieces:

* The SLNP Koha plugin, that implements convenient ways to handle the SLNP ILL configuration. Some
  helper APIs and hooks that aid process automation.
* A Koha ILL backend for **SLNP**, defining the workflows for ILL handling after the ILL requests
  are initiated by a regional ILL server using the SLNP protocol through a ZFL server.
* An _SLNP_ server, that can run as a daemon.

The remaining features of this ILL backend are accessible via the standard ILL framework in the Koha staff interface.

## Installing

### Search and install

Add the following snippet in the `<plugin_repos>` section of your `koha-conf.xml` file:

```xml
<repo>
    <name>BSZ</name>
    <org_name>BSZBW</org_name>
    <service>github</service>
</repo>
```

After restarting your services (including `memcached`) you will be able to search for _slnp_ on the plugins
management page.

### Manual install

Download this plugin from the [Releases page](https://github.com/BSZBW/koha-plugin-slnp-ill/releases) page.

## Updating

In order to upgrade, the install steps should be followed. The plugin includes an upgrade routine that
takes care of anything that is needed.

**IMPORTANT:** If you are upgrading from version _3.0.3_ or older, you will need to manually remove
the `plugins/Koha/Illbackends/SLNP` directory from your instance's home directory.

## Configuration

The plugin configuration is an HTML text area in which a _YAML_ structure is pasted. The available options
are maintained on this document.

```yaml
---
portal_url: https://your.portal.url
server:
  port: 9001
  ipv: '*'
  host: 127.0.0.1
  log_level: 3
fee_debit_type: ILL
default_fee: 2
charge_extra_fee_by_default: true
extra_fee_debit_type: ILL
category_fee:
  ST: null # no charge
  PT: 2
mandatory_lending_library: true
partner_category_code: IL
default_hold_note: Placed by ILL
default_framework: FA
default_ill_itype: BK
barcode_prefix: FL
pfl_number_prefix: "PREFIX "
title_prefix: "PREFIX "
title_suffix: " (SUFFIX)"
default_ill_branch: CPL
pickup_location_mapping:
  Campus Nord: MPL
  Campus Süden: FPL
item_types:
  loan: BK
  copy: CR
lending:
  denied_notforloan_values:
    - 1
    - 2
    - 3
  item_age:
    check: true
    days: 5
  control_borrowernumber: 123
  accepts_hold_requests: true
not_for_loan_after_auto_checkin: 1
lending_library:
  search_prefix: "<"
  search_suffix: ">"
  # where the sigel of the library is stored : surname || firstname || middle_name || othernames
  ill_library_id: "surname"
```

### not_for_loan_after_auto_checkin

For copies, which get auto-returned, we cannot perform the cleanup action right away,
because the checkin page requires the item to be present and it explodes otherwise. So,
instead, we set the status to `SLNP_COMP` and set the item `notforloan` status to a preset
default (1). This can be configured using the **not_for_loan_after_auto_checkin** entry.

### server.log_level

The `log_level` corresponds to the **Net::Server** logs levels. Only the following levels are used:

* 1: Only errors are logged.
* 3: All the transaction steps are logged, including the requests and intermediate response values.

## Running the SLNP server

The plugin bundles an SLNP server. The server code belongs to a specific Koha instance for which the plugin has been installed. If your instance is called _kohadev_, then you will start the server like this:

```shell
/path/to/the/plugins/dir/Koha/Plugin/Com/Theke/SLNP/scripts/slnp-server.sh --start kohadev
```

### Running at startup

In order to run the service at startup time, a _systemd unit file_ is provided.

```shell
$ export KOHA_INSTANCE=kohadev
# copy unit file
$ cp /var/lib/koha/${KOHA_INSTANCE}/plugins/Koha/Plugin/Com/Theke/SLNP/scripts/slnp-server.service \
     /etc/systemd/system/innreach_task_queue.service
# set KOHA_INSTANCE to match what you need (default: kohadev)
$ vim /etc/systemd/system/slnp-server.service
# reload unit files, including the new one
$ systemctl daemon-reload
# enable service
$ systemctl enable slnp-server.service
Created symlink /etc/systemd/system/multi-user.target.wants/slnp-server.service → /etc/systemd/system/slnp-server.service
# check the logs :-D
$ journalctl -u slnp-server.service -f

```

## Letters

The plugin introduces an API endpoint for generating the print notices.

Notice templates are handed the following attributes, depending on the context:

* illrequestattributes: a `Koha::ILL::Request::Attributes` iterator for `Koha::ILL::Request` objects.
* illrequest: The `Koha::ILL::Request` object.
* ill_bib_title: The generated record title field.
* ill_bib_author: The generated record author field.
* item: The linked `Koha::Item` object.
* lending_library: The `Koha::Patron` object representing the lending library.

To be removed (do not use):

* ill_full_metadata: Inherited from Koha, probably not useful besides debugging. Newline-separated list of `key: value` pairs for all metadata entries about the backend.

## Implemented hooks

This plugin implements several hooks that are required for using it:

* *intranet_js*
* *opac_js*
* *after_circ_action*
* *cronjob_nightly*

## Development

For developing the plugin, you need to have the plugins available in your [KTD](https://gitlab.com/koha-community/koha-testing-docker) environment:

```shell
export SYNC_REPO=/path/to/git/koha
export PLUGINS_DIR=/path/to/your/git/koha-plugins
export LOCAL_USER_ID=$(id -u)
ktd --proxy --name slnp --plugins up -d
```

As this with any other plugin development, the only way to trigger the install method
and thus have the plugin available on the UI, is to install it manually (in production,
this will be triggered automatically when you upload the _.kpz_ file):

```shell
$ ktd --name slnp --shell
$ misc/devel/install_plugins.pl
Installed SLNP ILL connector plugin for Koha version {VERSION}
All plugins successfully re-initialised
```

## About SLNP

SLNP (TM) (Simple Library Network Protocol) is a TCP network socket based protocol designed and introduced by the company Sisis Informationssysteme GmbH (later a part of OCLC) for their library management system SISIS-SunRise (TM).

This protocol supports the bussiness processes of libraries. A subset of SLNP that enables the communication required for regional an national ILL (Inter Library Loan) processes has been published by Sisis Informationssysteme GmbH as basis for connection of library management systems to ILL servers that use SLNP.

Sisis Informationssysteme GmbH / OCLC owns all rights to SLNP. SLNP is a registered trademark of Sisis Informationssysteme GmbH / OCLC.

## Credits

This plugin is based on the original ILL backend from [LMSCLoud GmbH](https://github.com/LMSCloud/ILLSLNPKoha).
