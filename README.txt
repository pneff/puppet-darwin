This is a puppet module used for deployments on Mac OS X systems. It patches
the `appdmg` and `darwinport` package providers. Additionally it offers two
new providers `appzip` and `pkgzip` that handle special cases of application
installation on the Mac.

Also it the `darwin::defaults` type to change default settings. Some examples
for its usage are applied by default.


Dependencies:
=============
Requires the `puppet-common` module: <http://github.com/pneff/puppet-common>.
Alternatively you can replace the two calls to `modules_dir` and
`modules_file` with the native puppet `file` type.
