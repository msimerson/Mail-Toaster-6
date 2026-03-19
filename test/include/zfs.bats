
setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  # Mock variables
  export ZFS_JAIL_VOL="zroot/jails"
  export ZFS_DATA_VOL="zroot/data"
  export ZFS_JAIL_MNT="/jails"
  export ZFS_DATA_MNT="/data"

  # Source the file under test
  load '../../include/zfs.sh'
}

# Mock tell_status
tell_status() { :; }

@test "zfs_filesystem_exists - exists" {
  zfs() {
    if [[ "$*" == "list -t filesystem myfs" ]]; then
      echo "myfs"
      return 0
    fi
    return 1
  }
  
  run zfs_filesystem_exists myfs
  assert_success
}

@test "zfs_filesystem_exists - does not exist" {
  zfs() { return 1; }
  
  run zfs_filesystem_exists myfs
  assert_failure
}

@test "zfs_create_fs - simple" {
  # Mock zfs to track calls
  zfs() {
    # If it's a list call, we want it to fail to simulate FS/mountpoint not existing
    if [[ "$1" == "list" ]]; then return 1; fi
    echo "zfs $*"
  }
  
  run zfs_create_fs myfs
  assert_success
  assert_output --partial "zfs create myfs"
}

@test "zfs_create_fs - with mountpoint" {
  zfs() {
    if [[ "$1" == "list" ]]; then return 1; fi
    echo "zfs $*"
  }
  
  run zfs_create_fs myfs /mnt/myfs
  assert_success
  assert_output --partial "zfs create -o mountpoint=/mnt/myfs myfs"
}
