# Glance

This is a small and simple linux shell script to send various details about your Storj node to Discord. There are settings that you can customize to choose what you see. Currently only made for 1 node.

## Prerequisites

Make sure you have the following installed (excluding discord.sh). The script has been tested on Debian 12 (Bookworm) with a Storj node setup using docker
- [git][git]
- [curl][curl]
- [jq][jq]
- [bc][bc]
- [discord.sh][discord]

## Installation

1. Clone the repository into your chosen directory and cd into the glance directory
```
cd ~/
git clone https://github.com/EleosVR/glance.git
cd ./glance/
```
2. Clone the raw [discord.sh][discord] file into the glance directory and set it to have executable permission
```
git clone https://raw.githubusercontent.com/fieu/discord.sh/master/discord.sh

chmod u+x ./discord.sh
or:
sudo chmod u+x ./discord.sh
```
3. [Create a webhook][webhook] in a text channel of your Discord server
4. Edit the settings.conf file and set your `DASHBOARD_URL` and `DISCORD_WEBHOOK` values. This is also where you can customize what you see in Discord (use `true` or `false`. Save the file when you are done
```
nano ./settings.conf
```
5. Execute the run.sh file from the glance directory
```
./run.sh
```

Make sure there are no errors in the terminal and everything looks good on Discord. The script takes about 2 seconds to run but this may depend on your setup. You can see an example below
![example output](/images/discord-output.jpg)

## Automation

If you would like to automate the script to run at any given time, we'll use crontab. I have mine running every hour which is what the code below will be. If you want to run it at a different interval, you could use a site like [crontab guru][crontab]
```
crontab -e

0 * * * * /home/pi/glance/run.sh >/dev/null 2>&1
```

## License

[GPL-3.0](https://www.gnu.org/licenses/gpl-3.0.en.html)

<!-- Links -->
[git]: https://git-scm.com/download/linux
[curl]: https://curl.se/
[jq]: https://jqlang.github.io/jq/
[bc]: https://www.gnu.org/software/bc/manual/html_mono/bc.html
[discord]: https://github.com/fieu/discord.sh
[webhook]: https://support.discord.com/hc/en-us/articles/228383668-Intro-to-Webhooks
[crontab]: https://crontab.guru/every-1-hour
