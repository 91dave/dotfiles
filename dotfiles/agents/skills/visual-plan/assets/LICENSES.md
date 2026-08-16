# Third-party components

Vendored files in this directory, and the one script loaded from a CDN at view
time. All are permissively licensed and redistributable.

## Vendored

### marked 18.0.9 — MIT

Markdown parser. Runs in Node at render time.
<https://github.com/markedjs/marked> · `marked.esm.js`

```
Copyright (c) 2018-2026, MarkedJS
Copyright (c) 2011-2018, Christopher Jeffrey

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

### highlight.js 11.12.0 — BSD-3-Clause

Syntax highlighting. Inlined into the rendered page and runs in the browser.
<https://github.com/highlightjs/highlight.js> · `highlight.min.js`,
`highlight-light.css` (github), `highlight-dark.css` (github-dark)

```
Copyright (c) 2006, Ivan Sagalaev. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice,
      this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice,
      this list of conditions and the following disclaimer in the documentation
      and/or other materials provided with the distribution.
    * Neither the name of the copyright holder nor the names of its
      contributors may be used to endorse or promote products derived from this
      software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE REGENTS AND CONTRIBUTORS BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## Loaded from a CDN

### mermaid 11.16.1 — MIT

Diagram rendering. Not vendored: the bundle is 3.4 MB, which is too large to
carry in git and to read across the WSL mount on every render.

Emitted only when a plan contains a `mermaid` fence, pinned to an exact version,
and guarded with Subresource Integrity so the browser refuses to execute
unexpected bytes:

```html
<script src="https://cdn.jsdelivr.net/npm/mermaid@11.16.1/dist/mermaid.min.js"
        integrity="sha384-aBQXj4hK6Jm05i7aQAsUV3bLdSUrHX1BGYfMB0166TtWt/RRaw+h0Eelme9OCOvy"
        crossorigin="anonymous"></script>
```

Regenerate the hash on any version bump, and update `MERMAID` in
`lib/render.mjs`:

```bash
curl -sL https://cdn.jsdelivr.net/npm/mermaid@<version>/dist/mermaid.min.js \
  | openssl dgst -sha384 -binary | openssl base64 -A
```

<https://github.com/mermaid-js/mermaid>

## Provenance of the skill itself

Derived from the `visual-plan` skill in
[BuilderIO/skills](https://github.com/BuilderIO/skills/tree/main/skills/visual-plan)
(MIT), built on [Agent-Native](https://github.com/BuilderIO/agent-native/) (MIT).
The authoring guidance is retained; the hosted renderer, MCP connector, and
canvas are not. See `README.md`.
