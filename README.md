One-Way Sync your TimeMachineBackups to Mega.nz

# why

I wanted to backup my TimeMachine sparsebundle files to mega, but mega sync has a 2-way sync and therefore I cannot be sure that it does not re-download locally deleted file parts of the SparseBundle

I then tried rclone, but it does not properly check the shasum of the files (if it does not match it goes back to file size compare)

So i built this tool.

Better make sure the sparsebundle is not changed during sync.
