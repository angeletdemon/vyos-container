system {
    host-name vyos-smoketest
    login {
        user admin {
            authentication {
                plaintext-password "admin"
            }
        }
    }
}
interfaces {
    ethernet eth1 {
        address 198.51.100.2/24
    }
}
