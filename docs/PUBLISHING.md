# Publishing the source repository

Publish source only. Do not upload your local game folder, WebAssembly engine, translated engine C, extracted shaders, additional game artwork, saves, mods, logs, diagnostic captures or compiled application packages.

The repository includes the original interface logo and background artwork; these are copyrighted images, not MIT-licensed code. Review their redistribution permissions separately before publication.

The root and app `.gitignore` files exclude local generated and private files. Ignore rules do not remove already tracked files, so inspect the index before pushing:

```sh
git status --short
git diff --cached --stat
git ls-files app/Generated app/GeneratedResources app/Tools app/Build mirror
```

The last command should print nothing. Inspect any other files you have added. Preserve LICENSE and the third-party notices. Do not describe open-source code as containing no copyrighted content: it is copyrighted code distributed under licenses.

For a new GitHub repository, create an empty repository named `GTA-V-Intel-Mac-Port` in your own account, then replace `YOUR_ACCOUNT` below:

```sh
git remote add origin https://github.com/YOUR_ACCOUNT/GTA-V-Intel-Mac-Port.git
git push -u origin main
```

If `origin` already exists, inspect it with `git remote -v` instead of overwriting it blindly. These commands publish the committed source; no remote or push is configured automatically by the preparation step.

A repository derived from upstream can acknowledge that relationship in its README even when uploaded as a new standalone repository. GitHub's own fork relationship is only established through its Fork workflow.

Before creating any binary release, review its actual contents and redistribution permissions separately. Locally built app bundles may contain material generated from the user's game files; ignoring them in Git does not make a binary release safe to distribute.
