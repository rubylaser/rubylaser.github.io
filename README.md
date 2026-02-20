# Zack Reed's Blog

This is the source code for my personal blog at [zackreed.me](https://zackreed.me), where I write about self-hosting, technology, cycling, and home lab projects.

The site is built with Jekyll and uses the Chirpy theme, hosted on GitHub Pages.

## About This Repository

This blog uses the **Chirpy Starter** template to provide a feature-rich blogging experience with minimal setup.

### Why This Template?

When installing the __Chirpy__ theme through __RubyGems.org__, Jekyll can only read files in the folders `_data`, `_layouts`, `_includes`, `_sass` and `assets`, as well as a small part of options of the `_config.yml` file from the theme's gem. If you have ever installed this theme gem, you can use the command `bundle info --path jekyll-theme-chirpy` to locate these files.

The Jekyll team claims that this is to leave the ball in the user's court, but this also results in users not being able to enjoy the out-of-the-box experience when using feature-rich themes.

To fully use all the features of Chirpy, you need to copy the other critical files from the theme's gem to your Jekyll site. The following is a list of targets:

```
.
├── _config.yml
├── _plugins
├── _tabs
└── index.html
```

This starter template extracts those files/configurations of the latest version of the Chirpy theme and the __CD__ workflow, so you can start writing in minutes.

## Setting Up Your Own Blog

If you'd like to create your own blog using this template:

### Prerequisites

Follow the instructions in the __Jekyll Docs__ to complete the installation of the basic environment. __Git__ also needs to be installed.

### Installation

1. Sign in to GitHub and __use this template__ to generate a brand new repository and name it `USERNAME.github.io`, where `USERNAME` represents your GitHub username.
2. Clone it to your local machine and run:

```bash
$ bundle
```

### Usage

Please see the __theme's docs__ for detailed configuration and usage information.

## License

This work is published under __MIT__ License.
