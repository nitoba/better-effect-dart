# Local plugin configuration

Copy the relevant `plugins:` section from `analysis_options.yaml` into the
application's top-level `analysis_options.yaml`, update the local path, and
restart the Dart Analysis Server.


The official plugin resolver currently expects an absolute path for a local
plugin. After publication, replace the path entry with a package version.
