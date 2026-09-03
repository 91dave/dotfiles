## Looking Up Source for Third-Party / NuGet / Internal Package Code

To read the source of a type from a NuGet package, an internal shared library, or
any dependency outside the current repo, find the source repo and read the `.cs` /
`.ts` directly. Do not rummage through `~/.nuget`, `bin/`, `obj/`, or decompile
DLLs — compiled binaries are noisy and symbol names rarely line up with the source.

```bash
# 1. Find it across the org (works for internal qtpkg-* packages)
gh search code --owner amdigital-co-uk "class WebsiteInfoModule"
gh search code --owner amdigital-co-uk --filename "WebsiteInfoModule.cs"

# 2. Already cloned? Read it locally
cd "$(repos resolve qtpkg-core)"

# 3. Not on disk, and cloning is overkill? Fetch the one file
gh api repos/amdigital-co-uk/qtpkg-core/contents/path/to/File.cs --jq .content | base64 -d
```

**Trigger:** any stack trace, type name, or behavioural question pointing at code outside the current repo (e.g. `Quartex.Common.*`, `Quartex.Core.*`, third-party middleware).
