# DEDVD

>> !!! `PLEASE DO NOT USE THIS FOR ANYTHING!` !!!

I take zero responsiblity legal, ethical, or otherwise if you lose data with this; It's "works for me" territory and that's all it is intended for.

---

> ### Our parents were so preoccupied with whether or not they could, they didn't stop to think if they should". 

The Kaiju-sized monstrosity of 'code' vs this kaiju-sized, monstrous, overwhellming feeling of dread my father has left me in the way of 100+ CDs / DVDs he put all the family: videos, photos, etc, on... that I'm going to attempt to rip, sort, and upload to an Immich instance.

This project is big, ugly, and mean; And only exists because throwing 30-50 bucks into it (the credits for copilot) -- was the only way I'd have the will power to actually go through with this "whole process". And barring notable oversight ... I'll hopefully never have touch this again, so while this is workable for my usecase I'm certainly not happy / proud how it came out. lol

It's basically `watch`s for a laser disc to be mounted, you name the directory to put resulting files in, rip said files, verify the checksums, then extract zips if there / possible. If it's a "video" disc, we have a `trans` command to transcode the media via HandbrakeCLI to a 720p 'HQ' mkv file (and given the time these were taken this is more than enough quality wise), `combine` to mash multiple other video filetypes into a mkv, then we can `upload` new files via rsync x ssh. We also have `rescue` that is just a redirect to photorec.

I know next-to nothing about how CD/DVDs are read, let alone proper backup procedures or even tooling, transcoding of them, etc, etc. This is a purpose-built program and 'works' despite itself & so I'll say one more time...

Please do not use this for anything.


### Note:

We are shipping Go libs via vendor in this repo; They are licensed individually and respectively to their original project(s).