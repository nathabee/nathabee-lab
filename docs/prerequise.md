# before install on the server we need

## before resetting server

#### make backup wordpress on nathabee.de in github

```bash
# with nathabee user
cd ~/nathabee-world
# update /data with all 3 wordpress datas and db
./scripts/updateAllArchive.sh
# send in github
./scripts/releaseAll.sh

```


## gh


(type -p wget >/dev/null || (sudo apt update && sudo apt install wget -y)) \
  && sudo mkdir -p -m 755 /etc/apt/keyrings \
  && out=$(mktemp) && wget -nv -O"$out" https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  && cat "$out" | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
  && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && sudo mkdir -p -m 755 /etc/apt/sources.list.d \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
  && sudo apt update \
  && sudo apt install gh -y


gh auth login

Then answer:

Where do you use GitHub? → GitHub.com

Preferred protocol for Git operations? → SSH

Upload your SSH public key? → No

How would you like to authenticate GitHub CLI? → Login with a web browser

Then verify:
https://github.com/login/device/
