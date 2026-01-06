
(define-constant err-amount-zero (err u100))
(define-constant err-project-not-found (err u101))
(define-constant err-project-inactive (err u102))
(define-constant err-not-owner (err u103))
(define-constant err-total-weight-zero (err u104))
(define-constant err-nothing-to-claim (err u105))
(define-constant err-insufficient-pool (err u106))

(define-constant sqrt-iterations (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19 u20))

;; Math helper for integer square root (Newton's method approx)
(define-private (sqrt-step (i uint) (state { guess: uint, n: uint }))
    (let ((g (get guess state))
          (n (get n state)))
        (let ((next (/ (+ g (/ n g)) u2)))
            { guess: next, n: n }
        )
    )
)

(define-private (square-gt (g uint) (n uint))
    (if (is-eq g u0)
        false
        (> g (/ n g))
    )
)

(define-private (sqrt-adjust (n uint) (g uint))
    (if (square-gt g n)
        (if (> g u0) (- g u1) u0)
        (let ((g1 (+ g u1)))
            (if (<= g1 (/ n g1)) g1 g)
        )
    )
)

(define-private (sqrt (n uint))
    (if (is-eq n u0)
        u0
        (let ((state (fold sqrt-step sqrt-iterations { guess: n, n: n })))
            (sqrt-adjust n (get guess state))
        )
    )
)

(define-data-var next-project-id uint u1)
(define-data-var matching-pool uint u0)

(define-map projects { id: uint } { owner: principal, active: bool })
(define-map project-stats { id: uint } { total-donations: uint, sqrt-sum: uint, donor-count: uint, matching-claimed: uint })
(define-map donor-stats { id: uint, donor: principal } { amount: uint })

(define-read-only (get-project (project-id uint))
    (map-get? projects { id: project-id })
)

(define-read-only (get-project-stats (project-id uint))
    (map-get? project-stats { id: project-id })
)

(define-read-only (get-donor-stats (project-id uint) (donor principal))
    (map-get? donor-stats { id: project-id, donor: donor })
)

(define-read-only (get-matching-pool)
    (var-get matching-pool)
)

(define-read-only (get-project-weight (project-id uint))
    (match (map-get? project-stats { id: project-id })
        stats (some (* (get sqrt-sum stats) (get sqrt-sum stats)))
        none
    )
)

(define-public (create-project)
    (let ((project-id (var-get next-project-id)))
        (map-set projects { id: project-id } { owner: tx-sender, active: true })
        (var-set next-project-id (+ project-id u1))
        (ok project-id)
    )
)

(define-public (set-project-active (project-id uint) (active bool))
    (match (map-get? projects { id: project-id })
        project
        (if (is-eq (get owner project) tx-sender)
            (begin
                (map-set projects { id: project-id } { owner: (get owner project), active: active })
                (ok true)
            )
            err-not-owner
        )
        err-project-not-found
    )
)

(define-public (donate (project-id uint) (amount uint))
    (if (is-eq amount u0)
        err-amount-zero
        (match (map-get? projects { id: project-id })
            project
            (if (not (get active project))
                err-project-inactive
                (let ((stats (default-to { total-donations: u0, sqrt-sum: u0, donor-count: u0, matching-claimed: u0 }
                                        (map-get? project-stats { id: project-id })))
                      (donor (default-to { amount: u0 }
                                        (map-get? donor-stats { id: project-id, donor: tx-sender })))
                      (prev-amount (get amount donor))
                      (new-amount (+ prev-amount amount))
                      (prev-sqrt (sqrt prev-amount))
                      (new-sqrt (sqrt new-amount))
                      (sqrt-delta (- new-sqrt prev-sqrt))
                      (new-donor-count (if (is-eq prev-amount u0)
                                           (+ (get donor-count stats) u1)
                                           (get donor-count stats))))
                    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
                    (map-set donor-stats { id: project-id, donor: tx-sender } { amount: new-amount })
                    (map-set project-stats { id: project-id }
                        {
                            total-donations: (+ amount (get total-donations stats)),
                            sqrt-sum: (+ sqrt-delta (get sqrt-sum stats)),
                            donor-count: new-donor-count,
                            matching-claimed: (get matching-claimed stats)
                        }
                    )
                    (ok true)
                )
            )
            err-project-not-found
        )
    )
)

(define-public (fund-matching (amount uint))
    (if (is-eq amount u0)
        err-amount-zero
        (begin
            (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
            (var-set matching-pool (+ (var-get matching-pool) amount))
            (ok true)
        )
    )
)

(define-public (claim-matching (project-id uint) (round-pool uint) (total-weight uint))
    (match (map-get? projects { id: project-id })
        project
        (if (not (is-eq (get owner project) tx-sender))
            err-not-owner
            (if (not (get active project))
                err-project-inactive
                (let ((stats (default-to { total-donations: u0, sqrt-sum: u0, donor-count: u0, matching-claimed: u0 }
                                        (map-get? project-stats { id: project-id })))
                      (weight (* (get sqrt-sum stats) (get sqrt-sum stats)))
                      (pool (var-get matching-pool)))
                    (if (or (is-eq total-weight u0) (is-eq round-pool u0))
                        err-total-weight-zero
                        (if (or (is-eq weight u0) (> (get matching-claimed stats) u0))
                            err-nothing-to-claim
                            (if (> round-pool pool)
                                err-insufficient-pool
                                (let ((share (/ (* round-pool weight) total-weight)))
                                    (if (or (is-eq share u0) (> share pool))
                                        err-insufficient-pool
                                        (begin
                                            (try! (stx-transfer? share (as-contract tx-sender) (get owner project)))
                                            (var-set matching-pool (- pool share))
                                            (map-set project-stats { id: project-id }
                                                {
                                                    total-donations: (get total-donations stats),
                                                    sqrt-sum: (get sqrt-sum stats),
                                                    donor-count: (get donor-count stats),
                                                    matching-claimed: share
                                                }
                                            )
                                            (ok share)
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
        err-project-not-found
    )
)
