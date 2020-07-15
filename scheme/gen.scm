(define (make-gen start update)
  (define state start)
  (lambda ()
    (let ((old state))
      (set! state (update state))
      old)))

(define (from start end)
  (make-gen start
            (lambda (x)
              (if (and x (< x end))
                (+ x 1)
                #f))))

(define (run gen)
  (let ((result (gen)))
    (if result
      (begin (display result)
             (newline)
             (run gen))
      'done)))

(run (from 0 10))
