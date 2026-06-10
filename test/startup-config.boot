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
