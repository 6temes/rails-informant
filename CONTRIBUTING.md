# Contributing

## Releasing

Publishing the release draft is the whole release: there is no version-bump commit, no local step and no API key.

1. Every push to `main` updates a draft GitHub release from the merged pull request titles. Its version bumps the highest published release: a pull request labelled `major` or `minor` bumps that part, and any other pull request bumps the patch.
2. Publish the draft. Its `vX.Y.Z` tag runs `release.yml`, which runs `ci.yml` on the tagged commit and, only if that passes, stamps the version into `lib/rails_informant/version.rb` with `bin/stamp-version`, builds the gem and pushes it through RubyGems trusted publishing in the `release` environment.

`lib/rails_informant/version.rb` holds the placeholder `0.0.1.dev` and is never bumped by hand.

Release Drafter skips prereleases: drafts are never prereleases, and a published prerelease is ignored when it picks the release to bump from.

The trusted publisher on rubygems.org must name workflow `release.yml` and environment `release`; a blank environment field accepts any environment. The release shape is described in the [Gem release section of the CI standard](https://github.com/6temes/claude-plugins/blob/main/docs/ci-standard.md#gem-release).

### Recovering from a failed publish

Release tags are never moved or deleted. Fix the cause and re-run the failed `publish` job on the same tag. If that tag cannot be released, because the tagged commit is broken or the run is too old to re-run, leave its tag and release in place and ship the fix as the next version. Before publishing that next draft, regenerate its notes by re-running the latest `Release Drafter` run on `main`, and add back any changes the failed release never shipped.
