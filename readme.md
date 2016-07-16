# Intended use
Create a desired setup for a HTPC after a clean Lubuntu install

# Install
Run the following commands:
```
sudo apt-get update
sudo apt-get install git
git clone https://github.com/supmagc/HtpcInit.git HtpcInit && sudo HtpcInit/main.sh
```

# Update
Run the following commands:
```
git -C HtpcInit pull && sudo HtpcInit/main.sh
```