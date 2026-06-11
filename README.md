
## Hosted ITS Host Operations

For safe restart/status/verification of hosted ITS hosts `6`, `70`, and `126`, use `mini/hostctl.sh`. It kills orphan simulator process groups, waits for ports to clear, restores clean packs, and verifies NCP reachability. See `docs/host-lifecycle.md`.

# Kurt's fork documentation

This fork tracks two separate work streams:

- Hosted ARPANET terminal fixes: see [docs/hosted-terminal-fixes.md](docs/hosted-terminal-fixes.md).
- Physical PiDP-10 external host integration: see [kurthamm/pidp10-arpanet-node](https://github.com/kurthamm/pidp10-arpanet-node).

The PiDP-10 work is intentionally kept in a separate companion repository because it documents home-lab replica hardware, IMP41 bridging, and overlay networking.

---

# Kurt's hosted terminal notes

This fork branch includes fixes for the hosted web terminal scenarios so the local terminal page can repeatedly connect to the intended ITS hosts:

- `@L 6` connects to ARPANET host `006`.
- `@L 70` connects to ARPANET host `106` and identifies as `MIT Dynamic Modelling PDP-10`.
- `@L 126` connects to ARPANET host `176`.

Hosts `6` and `126` may display `Unknown ITS PDP-10` in the ITS banner. That banner is from the ITS disk image; the routing is confirmed by the `TELNET to host ...` line.

The hosted terminal cleanup path now logs out of ITS before closing the local NCP telnet process, which prevents stale sessions from causing later `Open refused` or stalled connections.

---

# arpanet

WORK IN PROGRESS - Probably too early unless you are involved.

See the project in action (if we have the server up...) at https://obsolescence.dev/arpanet_home.html or run the setup on your own computer.

# Surf the Arpanet like it's 1972 again
This is the entry page for a faithful recreation of the Arpanet circa 1972-73, connecting replicas of the historical computers, running their recovered historical software, and talking to each other again over replica IMP routers - also running their original firmware. Explore the Arpanet and details of its nodes through the interactive chart below. Or read on to get a live terminal into the early 70s.
<br><br>
<b>This is work in progress! We hope to recover and reconstruct more and more Arpanet nodes over the coming months and years. Which is why, for now, this page is not published yet.</b>

<p align="center">
  <img width="45%" src="https://github.com/user-attachments/assets/0f15e12c-32c7-4e11-b749-cbcfac2c8092" />
  <img width="3%" src="https://github.com/user-attachments/assets/b12f9d23-c9e4-487f-8ea7-6813e5e96848" />
  <img width="45%" src="https://github.com/user-attachments/assets/61b43e18-ead0-488d-a556-a800fffb78d9" />
</p>
<br>
<img width="1916" height="960" alt="image" src="https://github.com/user-attachments/assets/5b03c509-ea3f-4941-a594-f89f749821bc" />
<br><br>
Arpanet. At first, not many people cared. The break-through came at the 1972 ICCC convention, known as the 'Arpanet Ball'. Attendees could get online, and were given a booklet with 'scenarios' to try for themselves.
No exaggeration - at the Arpanet Ball, the consequences of 'networking' suddenly became clear. 
<br><br>
So, it is interesting (actually, historically important!) to find out what exactly people saw at the event. Attendees could log themselves in on clunky Teletypes or very basic CRT terminals; they then could connect to the various computers on Arpanet and 'do things'. What things? That is why we recreated the Arpanet circa 1972-1973, and let you go through the 'Scenarios' yourself.
<br><br>

# Install
Clone, and run demo-run.sh. Inspect it for the things it does: (a) set up a local server, (b) a local client, both to get a terminal onto the web page, and (c) fire up the Arpanet itself.
<br><br>
Then, you can load the file arpanet_home.html into your browser. Or straight on to arpanet_terminal2.html if you want to skip the intro.
<br><br>
You might want to skip all the web stuff. A quick way straight onto your Arpanet is to run './do.sh 1'. That gets a TIP session, type @L 6 [return] and it will connect to host #6 on the Arpanet. That's an MIT ITS system.
<br><br>
The arpanet simulation consists of a network of IMP routers, which you can inspect and manage. The mini subdirectory contains the entire arpanet simulation, irrespective of the web server stuff. In ./mini, start by running ./impctl.py help. It will give you insight in how to play with the IMP farm. The hosts attached to the IMPs are started through ./mini/arpanet, they are started independently from the Arpanet IMP 'farm', but make sure you start ITS systems straight after starting their IMP. ITS is picky on when it wishes to hear from their IMP. Do 'screen -ls' to see the host systems themselves.
<br><br>
To stop, run stop-demo.sh.

<br>Dependencies: node.js, and Python websockets.
<br><br>
At the moment, do not expect much. We're building this up over the coming months.

# Structure

There is a fully formed but so far small Arpanet in ./mini. It consists of a network of (simh) simulated IMPs connecting to each other, and a number of (simh) PDP-10s and other machines. Many of the ones planned will run the reconstructed system software and applications from the period. Currently, there's just PDP-10s at MIT, typically hosts 70, 134 and 198and host 11, the Stanford SAIL system running WAITS. Host 11, alas, is not connected to the IMP through its own NCP software but through a Linuxbridge. UCLA's SDS Sigma 7 is planned soon. Longer term, the hope is for Multics, PDP-11s, and perhaps even IBM 360s. It is early days yet. But the IMPs run reliably, connecting to make their network over simulated leased lines; and we're happy with progress :-)
<br><br>
A more or less stand-alone web project runs the project page as well as the terminal page. All it does is get a terminal from the ./mini directory projected on to your browser page. A python simh-server script brings you into the ./mini Arpanet wolrd, and a python terminal_client handles the data flow with the ./arpanet_terminal.html file. The HTML file with the terminal_client script can run the web site remotely from the server on which the ./mini Arpanet is running.
<br><br>
More to come.
