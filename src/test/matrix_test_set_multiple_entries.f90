program matrix_test_set_multiple_entries

use sigma

    implicit none

    ! graph used as the matrix substrate
    type(ll_graph) :: g

    ! sparse and dense matrices
    class(sparse_matrix_interface), pointer :: A
    real(dp) :: B(2,2)

    ! integer indices
    integer :: i, j, k, d, nn, frmt
    integer :: is(2), js(2)
    integer, allocatable :: nodes(:)


    ! random numbers
    real(dp) :: p, w, z

    ! command-line argument parsing
    character(len=16) :: arg
    logical :: verbose



    !----------------------------------------------------------------------!
    ! Get command line arguments to see if we're running in verbose mode   !
    !----------------------------------------------------------------------!
    verbose = .false.
    call getarg(1,arg)
    select case(trim(arg))
        case("-v")
            verbose = .true.
        case("-V")
            verbose = .true.
        case("--verbose")
            verbose = .true.
    end select



    !----------------------------------------------------------------------!
    ! Set the matrix size and initialize a random seed                     !
    !----------------------------------------------------------------------!

    nn = 128
    p = log(1.0_dp * nn) / log(2.0_dp) / nn

    call init_seed()



    !----------------------------------------------------------------------!
    ! Make a random reference sparse matrix                                !
    !----------------------------------------------------------------------!
    call g%init(nn)

    do i = 1, nn
        call g%add_edge(i, i)

        do j = i + 1, nn
            call random_number(z)

            if (z < p) then
                call g%add_edge(i, j)
                call g%add_edge(j, i)
            endif
        enddo
    enddo

    d = g%get_max_degree()
    allocate(nodes(d))

    if (verbose) then
        print *, 'o Done generating random graph.'
        print *, '    Number of vertices:', nn
        print *, '    Number of edges:   ', g%get_num_edges()
        print *, '    Max vertex degree: ', d
    endif



    !----------------------------------------------------------------------!
    ! Test each matrix type                                                !
    !----------------------------------------------------------------------!
    B(:, 1) = [ 1.0, -1.0]
    B(:, 2) = [-1.0,  1.0]

    do frmt = 1, num_matrix_types
        if (verbose) print *, 'Format #',frmt

        !-----------------------------------------
        ! Choose a type for `A` and initialize it
        call choose_matrix_type(A, frmt)
        call A%init(nn, nn, g)
        call A%zero()

        !---------------------------
        ! Build the graph Laplacian
        do i = 1, nn
            call g%get_neighbors(nodes, i)
            d = g%get_degree(i)

            do k = 1, d
                j = nodes(k)
                if (j > i) then
                    is = [i, j]

                    call A%add_multiple_values(is, is, B)
                endif
            enddo
        enddo


        !------------------------------------------------
        ! Check that `A` actually is the graph Laplacian
        do i = 1, nn
            d = g%get_degree(i) - 1

            do j = 1, nn
                if (j == i) then
                    if (A%get_value(i, i) /= d) then
                        print *, 'Setting multiple matrix entries failed, '
                        print *, 'should have diagonal entry of each row '
                        print *, 'equal to its degree.'
                        print *, 'Degree of', i,':',d
                        print *, 'A(i, i) = ', A%get_value(i, i)
                        call exit(1)
                    endif
                elseif (g%connected(i, j)) then
                    if (A%get_value(i, j) /= -1) then
                        print *, 'Setting multiple matrix entries failed, '
                        print *, 'should have all off-diagonal entries '
                        print *, 'equal to -1.'
                        print *, 'i, j:', i, j
                        print *, 'A(i, j) = ', A%get_value(i, j)
                        call exit(1)
                    endif
                else
                    if (A%get_value(i, j) /= 0) then
                        print *, 'Erroneously set entry ', i, j
                        print *, 'of matrix which is not connected in the'
                        print *, 'input graph.'
                        print *, 'A(i, j) = ', A%get_value(i, j)
                        call exit(1)
                    endif
                endif
            enddo
        enddo


        ! Destroy the matrix so it's ready for the next test
        call A%destroy()
        deallocate(A)
    enddo   ! End of loop over frmt


    call g%destroy()


end program matrix_test_set_multiple_entries
