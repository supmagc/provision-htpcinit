# Intended use
Create a desired setup for a HTPC after a clean Lubuntu/Xubuntu install

# Install
Run the following commands:
```
sudo apt-get update
sudo apt-get install git
git clone https://github.com/supmagc/HtpcInit.git HtpcInit && cd HtpcInit && sudo ./main.sh && cd ../
```

# Update
Run the following commands:
```
git -C HtpcInit pull && cd HtpcInit && sudo ./main.sh && cd ../
```