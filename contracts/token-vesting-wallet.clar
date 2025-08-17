(define-constant ERR_UNAUTHORIZED (err u1))
(define-constant ERR_INVALID_AMOUNT (err u2))
(define-constant ERR_INVALID_DURATION (err u3))
(define-constant ERR_SCHEDULE_NOT_FOUND (err u4))
(define-constant ERR_ALREADY_CLAIMED (err u5))
(define-constant ERR_NOTHING_TO_CLAIM (err u6))
(define-constant ERR_INSUFFICIENT_BALANCE (err u7))
(define-constant ERR_INVALID_BENEFICIARY (err u8))
(define-constant ERR_SCHEDULE_ALREADY_EXISTS (err u9))
(define-constant ERR_ZERO_AMOUNT (err u10))

(define-data-var owner principal tx-sender)
(define-data-var token-contract principal .token-vesting-wallet)

(define-map vesting-schedules
  { beneficiary: principal }
  {
    total-amount: uint,
    claimed-amount: uint,
    start-time: uint,
    cliff-time: uint,
    duration: uint,
    created-by: principal,
    active: bool
  }
)

(define-map vesting-balances
  { beneficiary: principal }
  { balance: uint }
)

(define-read-only (get-owner)
  (var-get owner)
)

(define-read-only (get-token-contract)
  (var-get token-contract)
)

(define-read-only (get-vesting-schedule (beneficiary principal))
  (map-get? vesting-schedules { beneficiary: beneficiary })
)

(define-read-only (get-vesting-balance (beneficiary principal))
  (default-to { balance: u0 } (map-get? vesting-balances { beneficiary: beneficiary }))
)

(define-read-only (calculate-vested-amount (beneficiary principal))
  (let (
    (schedule (unwrap! (get-vesting-schedule beneficiary) (err u0)))
    (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    (start-time (get start-time schedule))
    (cliff-time (get cliff-time schedule))
    (duration (get duration schedule))
    (total-amount (get total-amount schedule))
  )
    (if (< current-time cliff-time)
      (ok u0)
      (if (>= current-time (+ start-time duration))
        (ok total-amount)
        (let (
          (elapsed-time (- current-time start-time))
          (vested-amount (/ (* total-amount elapsed-time) duration))
        )
          (ok vested-amount)
        )
      )
    )
  )
)

(define-read-only (get-claimable-amount (beneficiary principal))
  (let (
    (schedule (unwrap! (get-vesting-schedule beneficiary) (err u0)))
    (vested-amount (unwrap! (calculate-vested-amount beneficiary) (err u0)))
    (claimed-amount (get claimed-amount schedule))
  )
    (if (and (get active schedule) (> vested-amount claimed-amount))
      (ok (- vested-amount claimed-amount))
      (ok u0)
    )
  )
)

(define-read-only (get-remaining-time (beneficiary principal))
  (let (
    (schedule (unwrap! (get-vesting-schedule beneficiary) (err u0)))
    (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    (end-time (+ (get start-time schedule) (get duration schedule)))
  )
    (if (>= current-time end-time)
      (ok u0)
      (ok (- end-time current-time))
    )
  )
)

(define-read-only (is-fully-vested (beneficiary principal))
  (let (
    (schedule (unwrap! (get-vesting-schedule beneficiary) false))
    (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    (end-time (+ (get start-time schedule) (get duration schedule)))
  )
    (>= current-time end-time)
  )
)

(define-private (is-owner)
  (is-eq tx-sender (var-get owner))
)

(define-public (set-owner (new-owner principal))
  (begin
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    (var-set owner new-owner)
    (ok true)
  )
)

(define-public (set-token-contract (new-token-contract principal))
  (begin
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    (var-set token-contract new-token-contract)
    (ok true)
  )
)

(define-public (create-vesting-schedule 
  (beneficiary principal)
  (total-amount uint)
  (start-time uint)
  (cliff-duration uint)
  (vesting-duration uint)
)
  (let (
    (cliff-time (+ start-time cliff-duration))
    (existing-schedule (get-vesting-schedule beneficiary))
  )
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    (asserts! (> total-amount u0) ERR_ZERO_AMOUNT)
    (asserts! (> vesting-duration u0) ERR_INVALID_DURATION)
    (asserts! (not (is-eq beneficiary tx-sender)) ERR_INVALID_BENEFICIARY)
    (asserts! (is-none existing-schedule) ERR_SCHEDULE_ALREADY_EXISTS)
    
    (map-set vesting-schedules
      { beneficiary: beneficiary }
      {
        total-amount: total-amount,
        claimed-amount: u0,
        start-time: start-time,
        cliff-time: cliff-time,
        duration: vesting-duration,
        created-by: tx-sender,
        active: true
      }
    )
    
    (map-set vesting-balances
      { beneficiary: beneficiary }
      { balance: total-amount }
    )
    
    (ok true)
  )
)

(define-public (deposit-tokens (amount uint))
  (begin
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_ZERO_AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (ok true)
  )
)

(define-public (claim-tokens)
  (let (
    (schedule (unwrap! (get-vesting-schedule tx-sender) ERR_SCHEDULE_NOT_FOUND))
    (claimable-amount (unwrap! (get-claimable-amount tx-sender) ERR_NOTHING_TO_CLAIM))
    (current-claimed (get claimed-amount schedule))
  )
    (asserts! (get active schedule) ERR_SCHEDULE_NOT_FOUND)
    (asserts! (> claimable-amount u0) ERR_NOTHING_TO_CLAIM)
    
    (try! (as-contract (stx-transfer? claimable-amount tx-sender tx-sender)))
    
    (map-set vesting-schedules
      { beneficiary: tx-sender }
      (merge schedule { claimed-amount: (+ current-claimed claimable-amount) })
    )
    
    (ok claimable-amount)
  )
)

(define-public (revoke-vesting-schedule (beneficiary principal))
  (let (
    (schedule (unwrap! (get-vesting-schedule beneficiary) ERR_SCHEDULE_NOT_FOUND))
    (vested-amount (unwrap! (calculate-vested-amount beneficiary) ERR_SCHEDULE_NOT_FOUND))
    (claimed-amount (get claimed-amount schedule))
    (remaining-claimable (if (> vested-amount claimed-amount) (- vested-amount claimed-amount) u0))
    (unvested-amount (- (get total-amount schedule) vested-amount))
  )
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    (asserts! (get active schedule) ERR_SCHEDULE_NOT_FOUND)
    
    (if (> remaining-claimable u0)
      (try! (as-contract (stx-transfer? remaining-claimable tx-sender beneficiary)))
      true
    )
    
    (if (> unvested-amount u0)
      (try! (as-contract (stx-transfer? unvested-amount tx-sender (var-get owner))))
      true
    )
    
    (map-set vesting-schedules
      { beneficiary: beneficiary }
      (merge schedule { 
        active: false,
        claimed-amount: (get total-amount schedule)
      })
    )
    
    (ok { 
      vested-paid: remaining-claimable,
      unvested-returned: unvested-amount 
    })
  )
)

(define-public (update-vesting-schedule
  (beneficiary principal)
  (new-total-amount uint)
  (new-duration uint)
)
  (let (
    (schedule (unwrap! (get-vesting-schedule beneficiary) ERR_SCHEDULE_NOT_FOUND))
    (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    (vested-amount (unwrap! (calculate-vested-amount beneficiary) ERR_SCHEDULE_NOT_FOUND))
  )
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    (asserts! (get active schedule) ERR_SCHEDULE_NOT_FOUND)
    (asserts! (> new-total-amount u0) ERR_ZERO_AMOUNT)
    (asserts! (> new-duration u0) ERR_INVALID_DURATION)
    (asserts! (>= new-total-amount vested-amount) ERR_INVALID_AMOUNT)
    
    (map-set vesting-schedules
      { beneficiary: beneficiary }
      (merge schedule {
        total-amount: new-total-amount,
        duration: new-duration
      })
    )
    
    (ok true)
  )
)

(define-public (emergency-withdraw (amount uint))
  (begin
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_ZERO_AMOUNT)
    (try! (as-contract (stx-transfer? amount tx-sender (var-get owner))))
    (ok true)
  )
)

(define-read-only (get-contract-balance)
  (stx-get-balance (as-contract tx-sender))
)

(define-read-only (get-schedule-info (beneficiary principal))
  (let (
    (schedule (unwrap! (get-vesting-schedule beneficiary) (err u0)))
    (vested-amount (unwrap! (calculate-vested-amount beneficiary) (err u0)))
    (claimable-amount (unwrap! (get-claimable-amount beneficiary) (err u0)))
    (remaining-time (unwrap! (get-remaining-time beneficiary) (err u0)))
  )
    (ok {
      schedule: schedule,
      vested-amount: vested-amount,
      claimable-amount: claimable-amount,
      remaining-time: remaining-time,
      fully-vested: (is-fully-vested beneficiary)
    })
  )
)

(define-public (batch-create-schedules 
  (schedules (list 10 {
    beneficiary: principal,
    amount: uint,
    start-time: uint,
    cliff-duration: uint,
    duration: uint
  }))
)
  (begin
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    (fold create-single-schedule schedules (ok true))
  )
)

(define-private (create-single-schedule 
  (schedule-data {
    beneficiary: principal,
    amount: uint,
    start-time: uint,
    cliff-duration: uint,
    duration: uint
  })
  (prev-result (response bool uint))
)
  (match prev-result
    ok-value (create-vesting-schedule
      (get beneficiary schedule-data)
      (get amount schedule-data)
      (get start-time schedule-data)
      (get cliff-duration schedule-data)
      (get duration schedule-data)
    )
    err-value (err err-value)
  )
)

(define-read-only (get-multiple-schedules (beneficiaries (list 20 principal)))
  (map get-schedule-info beneficiaries)
)

(define-public (transfer-ownership (new-owner principal) (beneficiary principal))
  (let (
    (schedule (unwrap! (get-vesting-schedule beneficiary) ERR_SCHEDULE_NOT_FOUND))
  )
    (asserts! (is-eq tx-sender (get created-by schedule)) ERR_UNAUTHORIZED)
    (asserts! (get active schedule) ERR_SCHEDULE_NOT_FOUND)
    
    (map-set vesting-schedules
      { beneficiary: beneficiary }
      (merge schedule { created-by: new-owner })
    )
    
    (ok true)
  )
)
