# Domain Name Service Smart Contract

## About
This smart contract implements a decentralized domain name service on the Stacks blockchain. It allows users to register, manage, and transfer domain names while maintaining a secure and transparent record of ownership.

## Features
- Domain name registration with preorder-reveal pattern
- Domain ownership management
- Domain transfers
- Registration renewal
- DNS record management
- Resolver contract integration

## Contract Constants

### Error Codes
- `ERROR-DOMAIN-ALREADY-REGISTERED (u100)`: Domain name is already registered
- `ERROR-NOT-AUTHORIZED (u101)`: Transaction sender is not authorized
- `ERROR-DOMAIN-NOT-REGISTERED (u102)`: Domain name is not registered
- `ERROR-INVALID-DOMAIN-NAME (u103)`: Domain name does not meet length requirements
- `ERROR-DOMAIN-EXPIRED (u104)`: Domain registration has expired
- `ERROR-INSUFFICIENT-PAYMENT (u105)`: Payment amount is less than required

### Configuration
- Registration Period: ~1 year (52,560 blocks)
- Minimum Domain Length: 3 characters
- Maximum Domain Length: 63 characters
- Registration Fee: 100,000 microSTX

## Public Functions

### Domain Registration

#### `preorder-domain`
```clarity
(preorder-domain (domain-commitment-hash (buff 32)) (preorder-payment-ustx uint))
```
Initiates the domain registration process by submitting a hash commitment.
- Parameters:
  - `domain-commitment-hash`: Hash of domain name + salt
  - `preorder-payment-ustx`: Payment amount in microSTX

#### `register-domain`
```clarity
(register-domain (requested-domain-name (string-ascii 64)) (commitment-salt (buff 32)))
```
Completes the domain registration process by revealing the domain name.
- Parameters:
  - `requested-domain-name`: Actual domain name being registered
  - `commitment-salt`: Salt used in the preorder hash

### Domain Management

#### `transfer-domain`
```clarity
(transfer-domain (domain-name-to-transfer (string-ascii 64)) (new-owner-principal principal))
```
Transfers domain ownership to a new principal.

#### `renew-domain-registration`
```clarity
(renew-domain-registration (domain-name-to-renew (string-ascii 64)))
```
Extends domain registration for another year.

#### `set-domain-resolver`
```clarity
(set-domain-resolver (domain-name-to-update (string-ascii 64)) (new-resolver-principal (optional principal)))
```
Sets or updates the resolver contract for a domain.

#### `set-domain-record`
```clarity
(set-domain-record (domain-name-to-update (string-ascii 64)) (record-type (string-ascii 128)) (record-content (string-ascii 256)))
```
Sets DNS records for a domain.

## Read-Only Functions

### `get-domain-details`
```clarity
(get-domain-details (requested-domain-name (string-ascii 64)))
```
Returns all details associated with a domain.

### `get-domain-record`
```clarity
(get-domain-record (requested-domain-name (string-ascii 64)) (requested-record-type (string-ascii 128)))
```
Returns a specific DNS record for a domain.

### `is-domain-name-available`
```clarity
(is-domain-name-available (requested-domain-name (string-ascii 64)))
```
Checks if a domain name is available for registration.

### `get-domain-expiration`
```clarity
(get-domain-expiration (requested-domain-name (string-ascii 64)))
```
Returns the expiration block height for a domain.

## Usage Example

1. Preorder a domain:
```clarity
(contract-call? .dns preorder-domain 
    (hash160 (concat "mydomain.btc" 0x1234567890))
    u100000)
```

2. Register the domain:
```clarity
(contract-call? .dns register-domain 
    "mydomain.btc"
    0x1234567890)
```

3. Set a DNS record:
```clarity
(contract-call? .dns set-domain-record 
    "mydomain.btc"
    "A"
    "192.168.1.1")
```

## Security Considerations

1. **Preorder-Reveal Pattern**: The contract uses a commit-reveal scheme to prevent front-running during domain registration.
2. **Expiration Checks**: Domain operations are only permitted on non-expired domains.
3. **Authorization**: All modification operations require the transaction sender to be the current domain owner.
4. **Payment Verification**: Registration and renewal operations require correct payment amounts.

## Data Persistence

The contract maintains three main data maps:
- `domain-ownership-registry`: Stores domain ownership and registration details
- `domain-registration-preorders`: Manages domain preorder commitments
- `domain-dns-records`: Stores DNS records associated with domains

## Implementation Notes

1. Domain names are stored as ASCII strings with a maximum length of 64 characters.
2. DNS records support keys up to 128 characters and values up to 256 characters.
3. The contract uses block height for tracking registration periods and expiration.
4. All fees are burned as part of the registration process.

## Error Handling

The contract includes comprehensive error handling with specific error codes for different failure scenarios. All public functions return a response type that includes either success data or an error code.