;; title: Royalties-Streaming-per-View
;; version: 1.0.0
;; summary: A smart contract for streaming royalty payments to movie contributors per view



(define-non-fungible-token movie-nft uint)

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))
(define-constant err-listing-not-found (err u102))
(define-constant err-wrong-commission (err u103))
(define-constant err-already-minted (err u104))
(define-constant err-contributor-not-found (err u105))
(define-constant err-insufficient-balance (err u106))
(define-constant err-invalid-percentage (err u107))
(define-constant err-movie-not-found (err u108))

(define-data-var token-id-nonce uint u1)
(define-data-var platform-fee uint u250)

(define-map movies uint {
    title: (string-ascii 100),
    creator: principal,
    total-views: uint,
    price-per-view: uint,
    created-at: uint
})

(define-map contributors uint {
    movie-id: uint,
    contributor: principal,
    role: (string-ascii 20),
    percentage: uint
})

(define-map movie-contributors uint (list 20 uint))

(define-map contributor-earnings principal uint)

(define-map views uint {
    movie-id: uint,
    viewer: principal,
    timestamp: uint,
    payment-amount: uint
})

(define-map view-nonce uint uint)

(define-public (mint-movie (title (string-ascii 100)) (price-per-view uint) (to principal))
    (let
        (
            (token-id (var-get token-id-nonce))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (try! (nft-mint? movie-nft token-id to))
        (map-set movies token-id {
            title: title,
            creator: to,
            total-views: u0,
            price-per-view: price-per-view,
            created-at: stacks-block-height
        })
        (map-set view-nonce token-id u1)
        (var-set token-id-nonce (+ token-id u1))
        (ok token-id)
    )
)

(define-public (add-contributor (movie-id uint) (contributor principal) (role (string-ascii 20)) (percentage uint))
    (let
        (
            (movie (unwrap! (map-get? movies movie-id) err-movie-not-found))
            (contributor-id (get-next-contributor-id))
            (existing-contributors (default-to (list) (map-get? movie-contributors movie-id)))
        )
        (asserts! (is-eq tx-sender (get creator movie)) err-not-token-owner)
        (asserts! (<= percentage u10000) err-invalid-percentage)
        (map-set contributors contributor-id {
            movie-id: movie-id,
            contributor: contributor,
            role: role,
            percentage: percentage
        })
        (map-set movie-contributors movie-id (unwrap! (as-max-len? (append existing-contributors contributor-id) u20) err-invalid-percentage))
        (ok contributor-id)
    )
)

(define-public (stream-view (movie-id uint))
    (let
        (
            (movie (unwrap! (map-get? movies movie-id) err-movie-not-found))
            (price (get price-per-view movie))
            (current-views (get total-views movie))
            (view-id (unwrap! (map-get? view-nonce movie-id) err-movie-not-found))
            (platform-cut (/ (* price (var-get platform-fee)) u10000))
            (remaining-amount (- price platform-cut))
        )
        (try! (stx-transfer? price tx-sender contract-owner))
        (try! (distribute-royalties movie-id remaining-amount))
        (map-set views view-id {
            movie-id: movie-id,
            viewer: tx-sender,
            timestamp: stacks-block-height,
            payment-amount: price
        })
        (map-set movies movie-id (merge movie {total-views: (+ current-views u1)}))
        (map-set view-nonce movie-id (+ view-id u1))
        (ok view-id)
    )
)

(define-private (distribute-royalties (movie-id uint) (total-amount uint))
    (let
        (
            (contributor-ids (default-to (list) (map-get? movie-contributors movie-id)))
        )
        (fold distribute-to-contributor contributor-ids (ok total-amount))
    )
)

(define-private (distribute-to-contributor (contributor-id uint) (remaining-amount (response uint uint)))
    (match remaining-amount
        amount (let
            (
                (contributor-data (unwrap! (map-get? contributors contributor-id) err-contributor-not-found))
                (contributor-address (get contributor contributor-data))
                (percentage (get percentage contributor-data))
                (payout (/ (* amount percentage) u10000))
                (current-earnings (default-to u0 (map-get? contributor-earnings contributor-address)))
            )
            (if (> payout u0)
                (begin
                    (try! (as-contract (stx-transfer? payout tx-sender contributor-address)))
                    (map-set contributor-earnings contributor-address (+ current-earnings payout))
                    (ok (- amount payout))
                )
                (ok amount)
            )
        )
        error (err error)
    )
)

(define-public (withdraw-earnings)
    (let
        (
            (earnings (default-to u0 (map-get? contributor-earnings tx-sender)))
        )
        (asserts! (> earnings u0) err-insufficient-balance)
        (map-delete contributor-earnings tx-sender)
        (try! (as-contract (stx-transfer? earnings tx-sender tx-sender)))
        (ok earnings)
    )
)

(define-public (update-platform-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= new-fee u1000) err-invalid-percentage)
        (var-set platform-fee new-fee)
        (ok true)
    )
)

(define-public (transfer (token-id uint) (sender principal) (recipient principal))
    (begin
        (asserts! (is-eq tx-sender sender) err-not-token-owner)
        (try! (nft-transfer? movie-nft token-id sender recipient))
        (ok true)
    )
)

(define-read-only (get-owner (token-id uint))
    (ok (nft-get-owner? movie-nft token-id))
)

(define-read-only (get-last-token-id)
    (ok (- (var-get token-id-nonce) u1))
)

(define-read-only (get-token-uri (token-id uint))
    (ok none)
)

(define-read-only (get-movie-details (movie-id uint))
    (map-get? movies movie-id)
)

(define-read-only (get-contributor-details (contributor-id uint))
    (map-get? contributors contributor-id)
)

(define-read-only (get-movie-contributors (movie-id uint))
    (map-get? movie-contributors movie-id)
)

(define-read-only (get-contributor-earnings (contributor principal))
    (default-to u0 (map-get? contributor-earnings contributor))
)

(define-read-only (get-view-details (view-id uint))
    (map-get? views view-id)
)

(define-read-only (get-platform-fee)
    (var-get platform-fee)
)

(define-read-only (get-total-contributors)
    (var-get contributor-id-nonce)
)

(define-read-only (calculate-view-cost (movie-id uint))
    (match (map-get? movies movie-id)
        movie (ok (get price-per-view movie))
        (err err-movie-not-found)
    )
)

(define-read-only (get-movie-revenue (movie-id uint))
    (match (map-get? movies movie-id)
        movie (ok (* (get total-views movie) (get price-per-view movie)))
        (err err-movie-not-found)
    )
)

(define-data-var contributor-id-nonce uint u1)

(define-private (get-next-contributor-id)
    (let
        (
            (current-id (var-get contributor-id-nonce))
        )
        (var-set contributor-id-nonce (+ current-id u1))
        current-id
    )
)

(define-read-only (get-movie-stats (movie-id uint))
    (match (map-get? movies movie-id)
        movie (ok {
            title: (get title movie),
            creator: (get creator movie),
            total-views: (get total-views movie),
            price-per-view: (get price-per-view movie),
            total-revenue: (* (get total-views movie) (get price-per-view movie)),
            created-at: (get created-at movie)
        })
        (err err-movie-not-found)
    )
)

(define-public (bulk-add-contributors (movie-id uint) (contributors-data (list 10 {contributor: principal, role: (string-ascii 20), percentage: uint})))
    (let
        (
            (movie (unwrap! (map-get? movies movie-id) err-movie-not-found))
        )
        (asserts! (is-eq tx-sender (get creator movie)) err-not-token-owner)
        (fold add-single-contributor contributors-data (ok movie-id))
    )
)

(define-private (add-single-contributor (contributor-data {contributor: principal, role: (string-ascii 20), percentage: uint}) (movie-id-result (response uint uint)))
    (match movie-id-result
        movie-id (add-contributor movie-id (get contributor contributor-data) (get role contributor-data) (get percentage contributor-data))
        error (err error)
    )
)

(define-read-only (get-contributor-count (movie-id uint))
    (len (default-to (list) (map-get? movie-contributors movie-id)))
)

(define-public (batch-stream-views (movie-ids (list 5 uint)))
    (fold stream-single-view movie-ids (ok (list)))
)

(define-private (stream-single-view (movie-id uint) (results (response (list 5 uint) uint)))
    (match results
        success-list (match (stream-view movie-id)
            view-id (ok (unwrap! (as-max-len? (append success-list view-id) u5) err-invalid-percentage))
            error (err error)
        )
        error (err error)
    )
)

(define-read-only (get-top-movies (limit uint))
    (ok "Query not implemented - would return top movies by views")
)

(define-public (update-movie-price (movie-id uint) (new-price uint))
    (let
        (
            (movie (unwrap! (map-get? movies movie-id) err-movie-not-found))
        )
        (asserts! (is-eq tx-sender (get creator movie)) err-not-token-owner)
        (map-set movies movie-id (merge movie {price-per-view: new-price}))
        (ok true)
    )
)
