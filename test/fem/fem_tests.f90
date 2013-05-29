program fem_tests

    use meshes
    use linalg
    use fem

    implicit none

    ! computational mesh
    type(tri_mesh) :: mesh

    ! stiffness and mass matrices
    class(sparse_matrix), allocatable :: A,B,R

    ! some vectors
    real(kind(1d0)), allocatable :: u(:),v(:),f(:,:),g(:,:),z(:,:)

    ! solvers
    class(iterative_solver), allocatable :: krylov
    class(preconditioner), allocatable :: pc

    ! some other locals
    integer :: i,j,k,n
    integer, allocatable :: nbrs(:),mask(:)

!--------------------------------------------------------------------------!
! Read the mesh and do some initial stuff                                  !
!--------------------------------------------------------------------------!

    call read_mesh('../../meshes/circle.1',mesh)

    associate( nn=>mesh%nn, ne=>mesh%ne, nl=>mesh%nl, x=>mesh%x )

    allocate( u(nn),v(nn),g(2,ne),f(2,nn),z(2,nn) )
    allocate(csr_matrix::A)
    allocate(csr_matrix::B)

    call A%init(nn,nn,nn+2*nl)
    call B%init(nn,nn,nn+2*nl)



!--------------------------------------------------------------------------!
! Test assembly of finite element matrices                                 !
!--------------------------------------------------------------------------!
    call assemble(mesh,A)
    call assemble(mesh,B)

    allocate(nbrs(A%max_degree))
    nbrs = A%get_neighbors(1)



!--------------------------------------------------------------------------!
! Test filling of finite element matrices                                  !
!--------------------------------------------------------------------------!
    call stiffness_matrix(mesh,A,1.d0)
    call mass_matrix(mesh,B)

    v = 1.d0
    call A%matvec(u,v)

    if (maxval(dabs(u))>1.d-15) then
        print *, '|| A*[1.0,1.0,...,1.0] ||  should be 0 '
        print *, 'Value found: ',maxval(dabs(u))
    endif



!--------------------------------------------------------------------------!
! Test computing gradients of functions defined on FE mesh                 !
!--------------------------------------------------------------------------!
    do i=1,nn
        u(i) = 1.d0+x(1,i)+2*x(2,i)
    enddo

    g = 0.d0
    call gradient(mesh,u,g)

    f(1,:) = matvec_mass_matrix(mesh,g(1,:))
    f(2,:) = matvec_mass_matrix(mesh,g(2,:))

    call solver_setup(B,krylov,pc,pc_name='jacobi')
    allocate(mask(0))
    z = 0.d0
    call krylov%solve(B,z(1,:),f(1,:),pc,mask)
    call krylov%solve(B,z(2,:),f(2,:),pc,mask)

    if ( minval(z(1,:))<1.d0-1.d-8 .or. maxval(z(1,:))>1.d0+1.d-8 ) then
        print *, ' u(x,y) = 1+x+2y '
        print *, 'du/dx should be = 1'
        print *, 'Values found: (',minval(z(1,:)),',',maxval(z(1,:)),')'
    endif
    if ( minval(z(2,:))<2.d0-1.d-8 .or. maxval(z(2,:))>2.d0+1.d-8 ) then
        print *, ' u(x,y) = 1+x+2y '
        print *, 'du/dx should be = 2'
        print *, 'Values found: (',minval(z(2,:)),',',maxval(z(2,:)),')'
    endif


    end associate

end program fem_tests
