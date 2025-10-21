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
(define-constant err-price-locked (err u109))
(define-constant err-subscription-expired (err u110))
(define-constant err-subscription-active (err u111))
(define-constant err-invalid-tier (err u112))
(define-constant err-no-subscription (err u113))

(define-constant surge-threshold u10)
(define-constant surge-multiplier u150)
(define-constant price-cooldown-blocks u144)
(define-constant max-price-increase u300)
(define-constant min-price-decrease u50)
(define-constant viewing-window u20)

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

(define-map dynamic-pricing uint {
    current-price: uint,
    base-price: uint,
    surge-active: bool,
    last-adjustment: uint,
    recent-views: uint,
    price-locked-until: uint
})

(define-map viewing-patterns uint {
    hour-views: (list 24 uint),
    peak-hour: uint,
    average-views-per-block: uint
})

(define-map price-history uint {
    timestamp: uint,
    old-price: uint,
    new-price: uint,
    reason: (string-ascii 20)
})

(define-map subscriptions principal {
    tier: uint,
    expires-at: uint,
    total-views: uint,
    started-at: uint,
    auto-renew: bool
})

(define-map subscription-tiers uint {
    name: (string-ascii 20),
    price: uint,
    duration-blocks: uint,
    active: bool
})

(define-map subscription-views {subscriber: principal, view-id: uint} {
    movie-id: uint,
    timestamp: uint,
    watch-duration: uint
})

(define-map movie-subscription-stats uint {
    total-subscription-views: uint,
    total-watch-time: uint,
    subscriber-count: uint
})

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
        (map-set dynamic-pricing token-id {
            current-price: price-per-view,
            base-price: price-per-view,
            surge-active: false,
            last-adjustment: stacks-block-height,
            recent-views: u0,
            price-locked-until: u0
        })
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
            (dynamic-price (calculate-dynamic-price movie-id))
            (current-views (get total-views movie))
            (view-id (unwrap! (map-get? view-nonce movie-id) err-movie-not-found))
            (platform-cut (/ (* dynamic-price (var-get platform-fee)) u10000))
            (remaining-amount (- dynamic-price platform-cut))
        )
        (try! (stx-transfer? dynamic-price tx-sender contract-owner))
        (try! (distribute-royalties movie-id remaining-amount))
        (try! (update-viewing-metrics movie-id dynamic-price))
        (map-set views view-id {
            movie-id: movie-id,
            viewer: tx-sender,
            timestamp: stacks-block-height,
            payment-amount: dynamic-price
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
(define-data-var subscription-pool uint u0)
(define-data-var total-subscription-views uint u0)

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

(define-private (calculate-dynamic-price (movie-id uint))
    (match (map-get? dynamic-pricing movie-id)
        pricing
        (let
            (
                (base-price (get base-price pricing))
                (recent-views (get recent-views pricing))
                (current-block stacks-block-height)
                (blocks-since-adjustment (- current-block (get last-adjustment pricing)))
            )
            (if (> current-block (get price-locked-until pricing))
                (if (>= recent-views surge-threshold)
                    (let
                    (
                        (surge-price (/ (* base-price surge-multiplier) u100))
                        (max-allowed (/ (* base-price max-price-increase) u100))
                    )
                    (if (< surge-price max-allowed) surge-price max-allowed)
                )
                (if (and (< recent-views u3) (> blocks-since-adjustment viewing-window))
                    (let
                        (
                            (discount-price (/ (* base-price u90) u100))
                            (min-allowed (/ (* base-price min-price-decrease) u100))
                        )
                        (if (> discount-price min-allowed) discount-price base-price)
                    )
                    base-price
                )
            )
                (get current-price pricing)
            )
        )
        (match (map-get? movies movie-id)
            movie (get price-per-view movie)
            u0
        )
    )
)

(define-private (update-viewing-metrics (movie-id uint) (new-price uint))
    (let
        (
            (pricing (unwrap! (map-get? dynamic-pricing movie-id) err-movie-not-found))
            (current-block stacks-block-height)
            (blocks-since (- current-block (get last-adjustment pricing)))
            (views-to-track (if (< blocks-since viewing-window) (+ (get recent-views pricing) u1) u1))
        )
        (map-set dynamic-pricing movie-id
            (merge pricing {
                current-price: new-price,
                recent-views: views-to-track,
                last-adjustment: current-block,
                surge-active: (>= views-to-track surge-threshold),
                price-locked-until: (if (>= views-to-track surge-threshold) 
                                       (+ current-block price-cooldown-blocks) 
                                       (get price-locked-until pricing))
            })
        )
        (ok true)
    )
)

(define-read-only (get-current-price (movie-id uint))
    (match (map-get? dynamic-pricing movie-id)
        pricing (ok (get current-price pricing))
        (match (map-get? movies movie-id)
            movie (ok (get price-per-view movie))
            (err err-movie-not-found)
        )
    )
)

(define-read-only (get-surge-status (movie-id uint))
    (match (map-get? dynamic-pricing movie-id)
        pricing (ok {
            surge-active: (get surge-active pricing),
            current-price: (get current-price pricing),
            base-price: (get base-price pricing),
            recent-views: (get recent-views pricing),
            price-multiplier: (if (get surge-active pricing)
                                 (/ (* (get current-price pricing) u100) (get base-price pricing))
                                 u100)
        })
        (err err-movie-not-found)
    )
)

(define-read-only (get-price-analytics (movie-id uint))
    (match (map-get? dynamic-pricing movie-id)
        pricing (ok {
            current-price: (get current-price pricing),
            base-price: (get base-price pricing),
            surge-active: (get surge-active pricing),
            recent-views: (get recent-views pricing),
            locked-until: (get price-locked-until pricing),
            price-change-percentage: (if (> (get current-price pricing) (get base-price pricing))
                                        (/ (* (- (get current-price pricing) (get base-price pricing)) u100) (get base-price pricing))
                                        u0)
        })
        (err err-movie-not-found)
    )
)

(define-public (create-subscription-tier (tier-id uint) (name (string-ascii 20)) (price uint) (duration-blocks uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> price u0) err-invalid-percentage)
        (asserts! (> duration-blocks u0) err-invalid-percentage)
        (map-set subscription-tiers tier-id {
            name: name,
            price: price,
            duration-blocks: duration-blocks,
            active: true
        })
        (ok tier-id)
    )
)

(define-public (purchase-subscription (tier-id uint))
    (let
        (
            (tier (unwrap! (map-get? subscription-tiers tier-id) err-invalid-tier))
            (existing-sub (map-get? subscriptions tx-sender))
            (current-block stacks-block-height)
        )
        (asserts! (get active tier) err-invalid-tier)
        (asserts! (is-none existing-sub) err-subscription-active)
        (try! (stx-transfer? (get price tier) tx-sender contract-owner))
        (map-set subscriptions tx-sender {
            tier: tier-id,
            expires-at: (+ current-block (get duration-blocks tier)),
            total-views: u0,
            started-at: current-block,
            auto-renew: false
        })
        (var-set subscription-pool (+ (var-get subscription-pool) (get price tier)))
        (ok true)
    )
)

(define-public (renew-subscription)
    (let
        (
            (sub (unwrap! (map-get? subscriptions tx-sender) err-no-subscription))
            (tier (unwrap! (map-get? subscription-tiers (get tier sub)) err-invalid-tier))
            (current-block stacks-block-height)
        )
        (asserts! (get active tier) err-invalid-tier)
        (asserts! (< current-block (get expires-at sub)) err-subscription-expired)
        (try! (stx-transfer? (get price tier) tx-sender contract-owner))
        (map-set subscriptions tx-sender
            (merge sub {
                expires-at: (+ (get expires-at sub) (get duration-blocks tier))
            })
        )
        (var-set subscription-pool (+ (var-get subscription-pool) (get price tier)))
        (ok true)
    )
)

(define-public (stream-with-subscription (movie-id uint) (watch-duration uint))
    (let
        (
            (movie (unwrap! (map-get? movies movie-id) err-movie-not-found))
            (sub (unwrap! (map-get? subscriptions tx-sender) err-no-subscription))
            (current-block stacks-block-height)
            (movie-stats (default-to {
                total-subscription-views: u0,
                total-watch-time: u0,
                subscriber-count: u0
            } (map-get? movie-subscription-stats movie-id)))
            (view-id (+ (var-get total-subscription-views) u1))
        )
        (asserts! (< current-block (get expires-at sub)) err-subscription-expired)
        (map-set subscription-views {subscriber: tx-sender, view-id: view-id} {
            movie-id: movie-id,
            timestamp: current-block,
            watch-duration: watch-duration
        })
        (map-set subscriptions tx-sender
            (merge sub {
                total-views: (+ (get total-views sub) u1)
            })
        )
        (map-set movie-subscription-stats movie-id
            (merge movie-stats {
                total-subscription-views: (+ (get total-subscription-views movie-stats) u1),
                total-watch-time: (+ (get total-watch-time movie-stats) watch-duration)
            })
        )
        (var-set total-subscription-views view-id)
        (ok view-id)
    )
)

(define-public (distribute-subscription-revenue (movie-id uint))
    (let
        (
            (movie (unwrap! (map-get? movies movie-id) err-movie-not-found))
            (movie-stats (unwrap! (map-get? movie-subscription-stats movie-id) err-movie-not-found))
            (total-watch-time (get total-watch-time movie-stats))
            (pool-balance (var-get subscription-pool))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> total-watch-time u0) err-insufficient-balance)
        (asserts! (> pool-balance u0) err-insufficient-balance)
        (let
            (
                (platform-cut (/ (* pool-balance (var-get platform-fee)) u10000))
                (remaining-amount (- pool-balance platform-cut))
                (movie-share (/ (* remaining-amount total-watch-time) (var-get total-subscription-views)))
            )
            (try! (distribute-royalties movie-id movie-share))
            (var-set subscription-pool (- pool-balance movie-share))
            (ok movie-share)
        )
    )
)

(define-public (cancel-subscription)
    (let
        (
            (sub (unwrap! (map-get? subscriptions tx-sender) err-no-subscription))
        )
        (map-delete subscriptions tx-sender)
        (ok true)
    )
)

(define-public (toggle-auto-renew)
    (let
        (
            (sub (unwrap! (map-get? subscriptions tx-sender) err-no-subscription))
        )
        (map-set subscriptions tx-sender
            (merge sub {
                auto-renew: (not (get auto-renew sub))
            })
        )
        (ok true)
    )
)

(define-read-only (get-subscription (subscriber principal))
    (map-get? subscriptions subscriber)
)

(define-read-only (is-subscription-active (subscriber principal))
    (match (map-get? subscriptions subscriber)
        sub (ok (< stacks-block-height (get expires-at sub)))
        (ok false)
    )
)

(define-read-only (get-subscription-tier (tier-id uint))
    (map-get? subscription-tiers tier-id)
)

(define-read-only (get-movie-subscription-stats (movie-id uint))
    (map-get? movie-subscription-stats movie-id)
)

(define-read-only (get-subscription-pool-balance)
    (ok (var-get subscription-pool))
)

(define-read-only (get-subscription-view (subscriber principal) (view-id uint))
    (map-get? subscription-views {subscriber: subscriber, view-id: view-id})
)

(define-read-only (get-subscription-status (subscriber principal))
    (match (map-get? subscriptions subscriber)
        sub (ok {
            active: (< stacks-block-height (get expires-at sub)),
            tier: (get tier sub),
            expires-at: (get expires-at sub),
            blocks-remaining: (if (< stacks-block-height (get expires-at sub))
                                (- (get expires-at sub) stacks-block-height)
                                u0),
            total-views: (get total-views sub),
            auto-renew: (get auto-renew sub)
        })
        (err err-no-subscription)
    )
)
