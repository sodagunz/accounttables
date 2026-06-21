# accounttables

A lightweight acounting app for users who don't know anything about accounting.

This app is a simple tool that came to existance with the sole purpose of fixing the needs of my family business.
They have varying levels of accounting knowledge, and generally a bad level at excel, plus a lack of understanding of accrual/double-entry accounting.
As someone who's worked all his life in finance and accounting; I honestly struggle with that too sometimes.

The purpose of the app is to provide a user-friendly interface that allows users to do both movement and accrual accounting, with the ease of normal movement (cash) accounting. The main goal is to extract cash flow and predict short to mid term financial health. I'd also like to do some graphs.

## AI Disclaimer:

All human communication (prose, documentation) is my own prose. Machine communication is as close to 100% LLM output as I'd confortably accept; which probably is ~90% but may vary from time to time. 

This app is educatedly vibe-coded, as in "an educated guess". Some call it "agentic engineering", but I'm not even reading **all** of the code output so I don't think it can even be called that. I'm not a front end developer (you can probably tell from my choice of Elm). What can I say I just like strong typing. I'm just prompting my way around setting up UI, while being remaining very hands-on in relation to security and state management.

Back when I was a junior developer, I always found software architects were the most obnoxious type of people, setting up complex abstractions in a vacuum that seldom resisted the trial by fire that is running and maintaining a production app. I always blamed it on the fact that they didn't do much coding anymore. I don't really like the fact that the profession has devolved into code illiterate architects muttering commands to a stochastic machine who's really fast at generating poor code. Which is why I still code stuff manually when it gives me joy. This is not such a case: Front end does not give me joy; and I won't cripple myself from using a particular tool just because I don't like the people who build it.

You are, of course, fully entitled to disagree with my position and use Excel (or for ideological consistency, one of it's _libre_ clones). It's definitely more feature complete and has been running the world since long before I was born. It's also extremely impractical and unusable by the average folk running a small store.


## Development

This project facilitates a development shell via Nix. You can use it directly, or have it mount automatically when you `cd` into the project directory via `direnv`.

```sh
direnv allow
```

This will automatically enter the Nix shell when you `cd` into the project directory. Optionally, if you want to avoid `direnv`, you can enter the Nix shell directly with:

```sh
nix develop
```

Commands for building, linting and serving the Elm app are available within the Nix shell. They are pretty self-explanatory.

```sh
test
review
format
build-release #or build-release
run-local
```

If you are not familiar with Nix, you can still use the project without it; you just need to install the dependencies manually. Refer to `flake.nix` for a (hopefully exhaustive) list of dependencies.

## Auth/DB

The app uses Firebase Auth and Firestore. Configuration is done via `firebase-config.js`.
I will probably migrate away from Firebase in the future, but for now it's fast, easy and free; and it doesn't require a roundtrip through the Atlantic the same way deploying a server to my homelab would. If anyone knows a free and reliable VPS provider in latam, please let me know in an issue or something. I really need very, very small compute resources for this project, but I'd like to avoid the dynamic pricing that comes from cloud.
