# Releases

Each package is versioned and published independently. A package's tag starts its workflow.
For a coordinated family release, publish `better_effect` before
`better_effect_flutter` because the Flutter package depends on the matching hosted
core release line. The analyzer remains independent.

The repository uses a package-oriented layout: publishable libraries live under
`packages/`. The Flutter example and package-specific examples remain inside
their owning package so they are available in the package archive and can be
tested with the package's own dependencies.

The workflows deliberately publish from the commit referenced by the tag. Do
not move or reuse a release tag after pushing it.

| Package | `pubspec.yaml` version | Tag | pub.dev tag pattern |
| --- | --- | --- | --- |
| `better_effect` | `0.4.0` | `better_effect-v0.4.0` | `better_effect-v{{version}}` |
| `better_effect_flutter` | `0.4.0` | `better_effect_flutter-v0.4.0` | `better_effect_flutter-v{{version}}` |
| `better_effect_analyzer` | `0.4.0` | `better_effect_analyzer-v0.4.0` | `better_effect_analyzer-v{{version}}` |

## One-time pub.dev setup

Each package must exist on pub.dev before automated publishing can be enabled.
Publish the first version manually with `dart pub publish` or
`flutter pub publish`. Then, from that package's **Admin** page, enable
**Publishing from GitHub Actions** with:

- repository: `nitoba/better-effect-dart`;
- the tag pattern from the table above;
- the GitHub environment `pub.dev`.

Create an environment with that exact name in the repository settings before
pushing a release tag, and add any approval rules you want.

## Release a package

1. Update only that package's version and `CHANGELOG.md`.
2. Run the package checks locally.
3. Commit and push the changes.
4. Create a tag whose version exactly matches `pubspec.yaml`.
5. Push that tag.

For example:

```bash
git tag better_effect-v0.4.0
git push origin better_effect-v0.4.0
```

The other two workflows do not run. A failed or delayed release of one package
does not block another package's release.

## Security

The workflows use pub.dev's GitHub Actions OIDC publishing flow, so no long-
lived pub.dev token is stored in GitHub. Protect the three tag patterns with
repository tag rules and/or require approval on the `pub.dev` environment.
