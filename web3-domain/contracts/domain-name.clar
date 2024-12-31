;; Domain Name Service Contract

;; Error codes
(define-constant ERROR-DOMAIN-ALREADY-REGISTERED (err u100))
(define-constant ERROR-NOT-AUTHORIZED (err u101))
(define-constant ERROR-DOMAIN-NOT-REGISTERED (err u102))
(define-constant ERROR-INVALID-DOMAIN-NAME (err u103))
(define-constant ERROR-DOMAIN-EXPIRED (err u104))
(define-constant ERROR-INSUFFICIENT-PAYMENT (err u105))

;; Configuration Constants
(define-constant REGISTRATION-PERIOD-IN-BLOCKS u52560) ;; ~1 year in blocks
(define-constant MIN-DOMAIN-LENGTH u3)
(define-constant MAX-DOMAIN-LENGTH u63)
(define-constant REGISTRATION-FEE-IN_MICRO_STX u100000) ;; in microSTX

;; Data Maps
(define-map domain-ownership-registry
    {registered-domain-name: (string-ascii 64)}
    {
        current-owner: principal,
        expiration-block-height: uint,
        resolver-contract: (optional principal),
        initial-registration-block: uint,
        domain-commitment-hash: (buff 32)
    }
)

(define-map domain-registration-preorders
    {domain-commitment-hash: (buff 32)}
    {
        preorder-principal: principal,
        preorder-stx-amount: uint,
        preorder-creation-block: uint
    }
)

(define-map domain-dns-records
    {registered-domain-name: (string-ascii 64), dns-record-type: (string-ascii 128)}
    {dns-record-content: (string-ascii 256)}
)

;; Public functions

;; Preorder a domain (hash commitment)
(define-public (preorder-domain (domain-commitment-hash (buff 32)) (preorder-payment-ustx uint))
    (let
        (
            (preorder-data {
                preorder-principal: tx-sender,
                preorder-stx-amount: preorder-payment-ustx,
                preorder-creation-block: block-height
            })
        )
        (asserts! (>= preorder-payment-ustx REGISTRATION-FEE-IN_MICRO_STX) ERROR-INSUFFICIENT-PAYMENT)
        (try! (stx-burn? preorder-payment-ustx tx-sender))
        (ok (map-set domain-registration-preorders {domain-commitment-hash: domain-commitment-hash} preorder-data))
    )
)

;; Register a domain name
(define-public (register-domain (requested-domain-name (string-ascii 64)) (commitment-salt (buff 32)))
    (let
        (
            (calculated-commitment-hash (hash160 commitment-salt))  ;; Using just the salt for now
            (preorder-data (unwrap! (map-get? domain-registration-preorders {domain-commitment-hash: calculated-commitment-hash}) ERROR-DOMAIN-NOT-REGISTERED))
            (new-registration-entry {
                current-owner: tx-sender,
                expiration-block-height: (+ block-height REGISTRATION-PERIOD-IN-BLOCKS),
                resolver-contract: none,
                initial-registration-block: block-height,
                domain-commitment-hash: calculated-commitment-hash
            })
        )
        (asserts! (is-none (map-get? domain-ownership-registry {registered-domain-name: requested-domain-name})) ERROR-DOMAIN-ALREADY-REGISTERED)
        (asserts! (>= (len requested-domain-name) MIN-DOMAIN-LENGTH) ERROR-INVALID-DOMAIN-NAME)
        (asserts! (<= (len requested-domain-name) MAX-DOMAIN-LENGTH) ERROR-INVALID-DOMAIN-NAME)
        (asserts! (is-eq tx-sender (get preorder-principal preorder-data)) ERROR-NOT-AUTHORIZED)
        
        (map-delete domain-registration-preorders {domain-commitment-hash: calculated-commitment-hash})
        (ok (map-set domain-ownership-registry {registered-domain-name: requested-domain-name} new-registration-entry))
    )
)

;; Transfer domain ownership
(define-public (transfer-domain (domain-name-to-transfer (string-ascii 64)) (new-owner-principal principal))
    (let
        (
            (current-registration (unwrap! (map-get? domain-ownership-registry {registered-domain-name: domain-name-to-transfer}) ERROR-DOMAIN-NOT-REGISTERED))
        )
        (asserts! (is-eq tx-sender (get current-owner current-registration)) ERROR-NOT-AUTHORIZED)
        (asserts! (< block-height (get expiration-block-height current-registration)) ERROR-DOMAIN-EXPIRED)
        
        (ok (map-set domain-ownership-registry 
            {registered-domain-name: domain-name-to-transfer}
            (merge current-registration {current-owner: new-owner-principal})
        ))
    )
)

;; Renew domain registration
(define-public (renew-domain-registration (domain-name-to-renew (string-ascii 64)))
    (let
        (
            (current-registration (unwrap! (map-get? domain-ownership-registry {registered-domain-name: domain-name-to-renew}) ERROR-DOMAIN-NOT-REGISTERED))
        )
        (asserts! (is-eq tx-sender (get current-owner current-registration)) ERROR-NOT-AUTHORIZED)
        (try! (stx-burn? REGISTRATION-FEE-IN_MICRO_STX tx-sender))
        
        (ok (map-set domain-ownership-registry
            {registered-domain-name: domain-name-to-renew}
            (merge current-registration {
                expiration-block-height: (+ (get expiration-block-height current-registration) REGISTRATION-PERIOD-IN-BLOCKS)
            })
        ))
    )
)

;; Set resolver for domain
(define-public (set-domain-resolver (domain-name-to-update (string-ascii 64)) (new-resolver-principal (optional principal)))
    (let
        (
            (current-registration (unwrap! (map-get? domain-ownership-registry {registered-domain-name: domain-name-to-update}) ERROR-DOMAIN-NOT-REGISTERED))
        )
        (asserts! (is-eq tx-sender (get current-owner current-registration)) ERROR-NOT-AUTHORIZED)
        (asserts! (< block-height (get expiration-block-height current-registration)) ERROR-DOMAIN-EXPIRED)
        
        (ok (map-set domain-ownership-registry
            {registered-domain-name: domain-name-to-update}
            (merge current-registration {resolver-contract: new-resolver-principal})
        ))
    )
)

;; Set domain records
(define-public (set-domain-record (domain-name-to-update (string-ascii 64)) (record-type (string-ascii 128)) (record-content (string-ascii 256)))
    (let
        (
            (current-registration (unwrap! (map-get? domain-ownership-registry {registered-domain-name: domain-name-to-update}) ERROR-DOMAIN-NOT-REGISTERED))
        )
        (asserts! (is-eq tx-sender (get current-owner current-registration)) ERROR-NOT-AUTHORIZED)
        (asserts! (< block-height (get expiration-block-height current-registration)) ERROR-DOMAIN-EXPIRED)
        
        (ok (map-set domain-dns-records
            {registered-domain-name: domain-name-to-update, dns-record-type: record-type}
            {dns-record-content: record-content}
        ))
    )
)

;; Read-only functions

;; Get domain details
(define-read-only (get-domain-details (requested-domain-name (string-ascii 64)))
    (map-get? domain-ownership-registry {registered-domain-name: requested-domain-name})
)

;; Get domain record
(define-read-only (get-domain-record (requested-domain-name (string-ascii 64)) (requested-record-type (string-ascii 128)))
    (map-get? domain-dns-records {registered-domain-name: requested-domain-name, dns-record-type: requested-record-type})
)

;; Check domain availability
(define-read-only (is-domain-name-available (requested-domain-name (string-ascii 64)))
    (is-none (map-get? domain-ownership-registry {registered-domain-name: requested-domain-name}))
)

;; Get domain expiration
(define-read-only (get-domain-expiration (requested-domain-name (string-ascii 64)))
    (match (map-get? domain-ownership-registry {registered-domain-name: requested-domain-name})
        domain-registration-details (ok (get expiration-block-height domain-registration-details))
        ERROR-DOMAIN-NOT-REGISTERED
    )
)

;; Private functions

;; Validate domain name
(define-private (is-valid-domain-name (domain-name-to-validate (string-ascii 64)))
    (and
        (>= (len domain-name-to-validate) MIN-DOMAIN-LENGTH)
        (<= (len domain-name-to-validate) MAX-DOMAIN-LENGTH)
    )
)