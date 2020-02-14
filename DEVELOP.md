
## Testing

Mail Toaster 6 has two test suites:

### Continuous Integration

The CI tests are triggered automatically when a new PR is created and when a branch is pushed to. The CI tests are syntax only. They assure the bash code is syntactically correct and adheres to best practices.

The CI tests require no configuration. To run them, fork this repo, make your changes, push your new branch to your fork and then open a Pull Request. The tests will run automatically and you can see the results in the PR.


### Build tests

To do build tests, a FreeBSD host is required that has the ability to create jails. My FreeBSD test host is a VMware instance running on my iMac. In the `test` directory of this repo is a `vmware.sh` script that I use to revert the VM to a fresh state before each test build.

On my iMac I run the GitLab test runner. My gitlab_runner config looks like this:

```sh
$ cat ~/.gitlab-runner/config.toml
concurrent = 1
check_interval = 0

[[runners]]
  name = "imac27.simerson.net"
  url = "https://gitlab.com/"
  token = "longUniquishHexLookingString"
  executor = "ssh"
  [runners.ssh]
    user = "root"
    host = "10.0.1.119"
    identity_file = "/Users/matt/.ssh/id_rsa"
  [runners.cache]
```

The runner watches my GitLab repo and when changes are detected the runner connects to my VMware VM, checks out the project and runs a full test build, as configured in the GitLab configuration file `.gitlab-ci.yml`.

[Additional information here](https://github.com/msimerson/Mail-Toaster-6/wiki/Develop-CI-Testing).