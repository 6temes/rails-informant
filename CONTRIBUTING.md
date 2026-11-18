# Contributing

## Releasing

The release tag is the only source of the version. `lib/rails_informant/version.rb` holds the placeholder `0.0.1.dev` and is never bumped by hand.

1. Every push to `main` updates a draft GitHub release with the merged pull request titles. The draft's version is one step above the last published release, and prereleases are skipped when finding it. A pull request labelled `major` or `minor` bumps that part; any other pull request, labelled `patch` or not, bumps the patch.
2. Publish the draft. Its `v<version>` tag runs the `Release` workflow, which runs the CI suite on the tagged commit and, only if it passes, stamps the version into `version.rb` with `bin/stamp-version`, builds the gem and pushes it through RubyGems trusted publishing in the `release` environment.

The rubygems.org trusted publisher must name workflow `release.yml` and environment `release`.

### Recovering from a failed publish

Release tags are never moved or deleted. Fix the cause and re-run the failed `publish` job on the same tag. If that tag cannot be released, leave it in place and ship the fix as the next version. Before publishing that next draft, regenerate its notes by re-running the latest `Release Drafter` run on `main`.
