#include "erl_nif.h"
#include "cublas.h"
#include "stdio.h"
#include "time.h"


#define IDX2C(i,j,ld) (((j)*(ld))+(i))
#define DEBUG return(enif_make_int(env, 0));
#define PI 3.14159265358979323846
#define SIGMOID(x)  (1 / (1+exp(-1*x)))



static ERL_NIF_TERM
print1(ErlNifEnv *env, int argc, const ERL_NIF_TERM *argv) {
    ErlNifBinary  a_bin;
    ERL_NIF_TERM  result;
    float        *a;
    int r,c,i,j;


    if (!enif_get_int(env, argv[0], &r )) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &c )) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[2], &a_bin )) return enif_make_badarg(env);
    
    a  = (float *) a_bin.data;
  
    for(i=0;i<r;i++){
        for(j=0;j<c;j++){
            printf("%f ", a[IDX2C(i,j,r)]);
        }
        printf("\n\r"); 
    }
    printf("\n\r"); 
    result = enif_make_atom(env,"true");

    return result;
}


static ERL_NIF_TERM
new1(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    int n,i;
    ERL_NIF_TERM a_bin;
    float *a;
    double d;

    enif_get_int(env, argv[0], &n);
    enif_get_double(env, argv[1], &d);
    a = (float *) enif_make_new_binary(env, n * sizeof(float), &a_bin);

    // Set matrix data 
    for(i=0;i<n;i++){
        a[i] = (float)d;
    }

    return(a_bin);
}



static ERL_NIF_TERM
new2(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    int r1,c1,i,j;
    ERL_NIF_TERM head, list, a_bin;
    float *a;
    double d;

    enif_get_int(env, argv[0], &r1);
    enif_get_int(env, argv[1], &c1);
    a = (float *) enif_make_new_binary(env, r1 * c1 * sizeof(float), &a_bin);

    // Set matrix data 
    list = argv[2]; /* matrix1 */
    for(i=0;i<r1;i++){
        for(j=0;j<c1;j++){
            enif_get_list_cell(env, list, &head, &list);
            enif_get_double(env,head,&d);
            a[IDX2C(i,j,r1)] = (float)d;
        }
    }

    return(a_bin);
}



static ERL_NIF_TERM
rand1(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    int n,i;
    float x,y,val;
    float *result_data;
    ERL_NIF_TERM result;

    enif_get_int(env, argv[0], &n);
    result_data = (float *) enif_make_new_binary(env, n * sizeof(float), &result);

    srand((unsigned) time(NULL));
    for(i=0;i<n;i++){
        //box_muller
        x = (float)rand()/(float)RAND_MAX;
        y = (float)rand()/(float)RAND_MAX;
        val = sqrt(-2.0 * log(x)) * cos(2.0 * PI * y);
        result_data[i] = val;
    }
    return(result);
}



static ERL_NIF_TERM
mult(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary  a_bin, b_bin;
    ERL_NIF_TERM  c_bin;
    int r1, c1, r2, c2, n, i, j;
    float *a,*b,*c;
    cublasStatus stat;
    float* devPtrA;
    float* devPtrB;
    float* devPtrC;


    if (!enif_get_int(env, argv[0], &r1)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &c1)) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[2], &a_bin )) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[3], &r2)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[4], &c2)) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[5], &b_bin)) return enif_make_badarg(env);
    n = r1*c2;
    a = (float *) a_bin.data;
    b = (float *) b_bin.data;
    c = (float *) enif_make_new_binary(env, n * sizeof(float), &c_bin);

    for(j=0;j<c2;j++)
        for(i=0;i<r1;i++)
            c[IDX2C(i,j,r1)] = 0.0;


    // Initialize CUBLAS
    cublasInit();

    stat = cublasAlloc (r1*c1, sizeof(*a), (void**)&devPtrA);
    if(stat != CUBLAS_STATUS_SUCCESS)
        return(enif_make_int(env, 0)); 
    stat = cublasAlloc (r2*c2, sizeof(*b), (void**)&devPtrB);
    if(stat != CUBLAS_STATUS_SUCCESS)
        return(enif_make_int(env, 0)); 
    stat = cublasAlloc (r1*c2, sizeof(*c), (void**)&devPtrC);
    if(stat != CUBLAS_STATUS_SUCCESS)
        return(enif_make_int(env, 0)); 

    stat = cublasSetMatrix (r1, c1, sizeof(*a), a, r1, devPtrA, r1);
    if(stat != CUBLAS_STATUS_SUCCESS)
        return(enif_make_int(env, 0)); 
    stat = cublasSetMatrix (r2, c2, sizeof(*b), b, r2, devPtrB, r2);
    if(stat != CUBLAS_STATUS_SUCCESS)
        return(enif_make_int(env, 0)); 
    stat = cublasSetMatrix (r1, c2, sizeof(*c), c, r1, devPtrC, r1);
    if(stat != CUBLAS_STATUS_SUCCESS)
        return(enif_make_int(env, 0)); 


    //Sgemm
    cublasSgemm('N', 'N', r1, c2, c1, 1.0, devPtrA, r1, devPtrB, r2, 0.0, devPtrC, r1);


    stat = cublasGetMatrix (r1, c2, sizeof(*c), devPtrC, r1, c, r1);
    if(stat != CUBLAS_STATUS_SUCCESS){
        cublasFree(devPtrA);
        cublasFree(devPtrB);
        cublasFree(devPtrC);
        cublasShutdown();
        return(enif_make_int(env, 0)); 
    }

    // Shutdown CUBLAS
    cublasFree(devPtrA);
    cublasFree(devPtrB);
    cublasFree(devPtrC);
    cublasShutdown();
    

    return(c_bin);

}


__global__ void add1_kernel(float *a, float *b, float *c, int n)
{
	int tid = threadIdx.x + blockIdx.x * blockDim.x;
	while (tid < n)
	{
		c[tid] = a[tid] + b[tid];
		tid += blockDim.x * gridDim.x;
	}
}



static ERL_NIF_TERM
add1(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary  a_bin, b_bin;
    ERL_NIF_TERM  c_bin;
    int r1, c1, n;
    float *a,*b,*c;
    float *dev_a, *dev_b, *dev_c;

    if (!enif_get_int(env, argv[0], &r1)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &c1)) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[2], &a_bin )) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[3], &b_bin)) return enif_make_badarg(env);
    n = r1*c1;
    a = (float *) a_bin.data;
    b = (float *) b_bin.data;
    c = (float *) enif_make_new_binary(env, n * sizeof(float), &c_bin);

    	// Allocate for GPU
	cudaMalloc((void**)&dev_a, n * sizeof(float));
	cudaMalloc((void**)&dev_b, n * sizeof(float));
	cudaMalloc((void**)&dev_c, n * sizeof(float));


    // copy from host a,b to GPU dev_a, dev_b
	cudaMemcpy(dev_a, a, n * sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(dev_b, b, n * sizeof(float), cudaMemcpyHostToDevice);

	add1_kernel << <128, 128 >> >(dev_a, dev_b, dev_c, n);

	// copy to host c from GPU dev_c
	cudaMemcpy(c, dev_c, n * sizeof(float), cudaMemcpyDeviceToHost);

    // free 
    cudaFree(dev_a);
	cudaFree(dev_b);
	cudaFree(dev_c);

    return(c_bin);
}

__global__ void sub1_kernel(float *a, float *b, float *c, int n)
{
	int tid = threadIdx.x + blockIdx.x * blockDim.x;
	while (tid < n)
	{
		c[tid] = a[tid] - b[tid];
		tid += blockDim.x * gridDim.x;
	}
}
static ERL_NIF_TERM
sub1(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary  a_bin, b_bin;
    ERL_NIF_TERM  c_bin;
    int r1, c1, n;
    float *a,*b,*c;
    float *dev_a, *dev_b, *dev_c;

    if (!enif_get_int(env, argv[0], &r1)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &c1)) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[2], &a_bin )) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[3], &b_bin)) return enif_make_badarg(env);
    n = r1*c1;
    a = (float *) a_bin.data;
    b = (float *) b_bin.data;
    c = (float *) enif_make_new_binary(env, n * sizeof(float), &c_bin);

    	// Allocate for GPU
	cudaMalloc((void**)&dev_a, n * sizeof(float));
	cudaMalloc((void**)&dev_b, n * sizeof(float));
	cudaMalloc((void**)&dev_c, n * sizeof(float));


    // copy from host a,b to GPU dev_a, dev_b
	cudaMemcpy(dev_a, a, n * sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(dev_b, b, n * sizeof(float), cudaMemcpyHostToDevice);

	sub1_kernel << <128, 128 >> >(dev_a, dev_b, dev_c, n);

	// copy to host c from GPU dev_c
	cudaMemcpy(c, dev_c, n * sizeof(float), cudaMemcpyDeviceToHost);

    // free 
    cudaFree(dev_a);
	cudaFree(dev_b);
	cudaFree(dev_c);

    return(c_bin);
}


__global__ void emult1_kernel(float *a, float *b, float *c, int n)
{
	int tid = threadIdx.x + blockIdx.x * blockDim.x;
	while (tid < n)
	{
		c[tid] = a[tid] * b[tid];
		tid += blockDim.x * gridDim.x;
	}
}


static ERL_NIF_TERM
emult1(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary  a_bin, b_bin;
    ERL_NIF_TERM  c_bin;
    int r1, c1, n;
    float *a,*b,*c;
    float *dev_a, *dev_b, *dev_c;

    if (!enif_get_int(env, argv[0], &r1)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &c1)) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[2], &a_bin )) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[3], &b_bin)) return enif_make_badarg(env);
    n = r1*c1;
    a = (float *) a_bin.data;
    b = (float *) b_bin.data;
    c = (float *) enif_make_new_binary(env, n * sizeof(float), &c_bin);

    	// Allocate for GPU
	cudaMalloc((void**)&dev_a, n * sizeof(float));
	cudaMalloc((void**)&dev_b, n * sizeof(float));
	cudaMalloc((void**)&dev_c, n * sizeof(float));


    // copy from host a,b to GPU dev_a, dev_b
	cudaMemcpy(dev_a, a, n * sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(dev_b, b, n * sizeof(float), cudaMemcpyHostToDevice);

	emult1_kernel << <128, 128 >> >(dev_a, dev_b, dev_c, n);

	// copy to host c from GPU dev_c
	cudaMemcpy(c, dev_c, n * sizeof(float), cudaMemcpyDeviceToHost);

    // free 
    cudaFree(dev_a);
	cudaFree(dev_b);
	cudaFree(dev_c);

    return(c_bin);
}


static ERL_NIF_TERM
transpose1(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary  a_bin;
    ERL_NIF_TERM  b_bin;
    int r1, c1, n, i, j;
    float *a,*b;

    if (!enif_get_int(env, argv[0], &r1)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &c1)) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[2], &a_bin )) return enif_make_badarg(env);
    n = r1*c1;
    a = (float *) a_bin.data;
    b = (float *) enif_make_new_binary(env, n * sizeof(float), &b_bin);

    for(i=0;i<r1;i++){
        for(j=0;j<c1;j++){
            b[IDX2C(j,i,c1)] = a[IDX2C(i,j,r1)];
        }
    }

    return(b_bin);
}


static ERL_NIF_TERM
ident1(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    int n,i,j;
    ERL_NIF_TERM a_bin;
    float *a;

    enif_get_int(env, argv[0], &n);
    a = (float *) enif_make_new_binary(env, n * n * sizeof(float), &a_bin);

    // Set matrix data 
    for(i=0;i<n;i++){
        for(j=0;j<n;j++){
            if(i==j)
                a[IDX2C(i,j,n)] = 1.0;
            else
                a[IDX2C(i,j,n)] = 0.0;
        }
    }

    return(a_bin);
}




__global__ void sigmoid_kernel(float *a, float *b, int n)
{
	int tid = threadIdx.x + blockIdx.x * blockDim.x;
	while (tid < n)
	{   
        b[tid] = SIGMOID(a[tid]);
		tid += blockDim.x * gridDim.x;
	}
}

static ERL_NIF_TERM
activate_sigmoid(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary  a_bin;
    ERL_NIF_TERM  b_bin;
    int r1, c1, n;
    float *a,*b;
    float *dev_a, *dev_b;

    if (!enif_get_int(env, argv[0], &r1)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &c1)) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[2], &a_bin )) return enif_make_badarg(env);
    n = r1*c1;
    a = (float *) a_bin.data;
    b = (float *) enif_make_new_binary(env, n * sizeof(float), &b_bin);

    	// Allocate for GPU
	cudaMalloc((void**)&dev_a, n * sizeof(float));
	cudaMalloc((void**)&dev_b, n * sizeof(float));


    // copy from host a,b to GPU dev_a, dev_b
	cudaMemcpy(dev_a, a, n * sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(dev_b, b, n * sizeof(float), cudaMemcpyHostToDevice);

	sigmoid_kernel << <128, 128 >> >(dev_a, dev_b, n);

	// copy to host c from GPU dev_c
	cudaMemcpy(b, dev_b, n * sizeof(float), cudaMemcpyDeviceToHost);

    return(b_bin);
}


__global__ void differ_sigmoid_kernel(float *a, float *b, int n)
{
	int tid = threadIdx.x + blockIdx.x * blockDim.x;
	while (tid < n)
	{   
        b[tid] = (1 - SIGMOID(a[tid])) * SIGMOID(a[tid]);
		tid += blockDim.x * gridDim.x;
	}
}



__global__ void tanh_kernel(float *a, float *b, int n)
{
	int tid = threadIdx.x + blockIdx.x * blockDim.x;
	while (tid < n)
	{
		b[tid] = tanh(a[tid]);
		tid += blockDim.x * gridDim.x;
	}
}


static ERL_NIF_TERM
activate_tanh(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary  a_bin;
    ERL_NIF_TERM  b_bin;
    int r1, c1, n;
    float *a,*b;
    float *dev_a, *dev_b;

    if (!enif_get_int(env, argv[0], &r1)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &c1)) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[2], &a_bin )) return enif_make_badarg(env);
    n = r1*c1;
    a = (float *) a_bin.data;
    b = (float *) enif_make_new_binary(env, n * sizeof(float), &b_bin);

    	// Allocate for GPU
	cudaMalloc((void**)&dev_a, n * sizeof(float));
	cudaMalloc((void**)&dev_b, n * sizeof(float));


    // copy from host a,b to GPU dev_a, dev_b
	cudaMemcpy(dev_a, a, n * sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(dev_b, b, n * sizeof(float), cudaMemcpyHostToDevice);

	tanh_kernel << <128, 128 >> >(dev_a, dev_b, n);

	// copy to host c from GPU dev_c
	cudaMemcpy(b, dev_b, n * sizeof(float), cudaMemcpyDeviceToHost);

    return(b_bin);
}



__global__ void relu_kernel(float *a, float *b, int n)
{
	int tid = threadIdx.x + blockIdx.x * blockDim.x;
	while (tid < n)
	{   
        if(a[tid] >= 0)
		    b[tid] = a[tid];
        else 
            b[tid] = 0.0;
		tid += blockDim.x * gridDim.x;
	}
}


static ERL_NIF_TERM
activate_relu(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary  a_bin;
    ERL_NIF_TERM  b_bin;
    int r1, c1, n;
    float *a,*b;
    float *dev_a, *dev_b;

    if (!enif_get_int(env, argv[0], &r1)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &c1)) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[2], &a_bin )) return enif_make_badarg(env);
    n = r1*c1;
    a = (float *) a_bin.data;
    b = (float *) enif_make_new_binary(env, n * sizeof(float), &b_bin);

    	// Allocate for GPU
	cudaMalloc((void**)&dev_a, n * sizeof(float));
	cudaMalloc((void**)&dev_b, n * sizeof(float));


    // copy from host a,b to GPU dev_a, dev_b
	cudaMemcpy(dev_a, a, n * sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(dev_b, b, n * sizeof(float), cudaMemcpyHostToDevice);

	relu_kernel << <128, 128 >> >(dev_a, dev_b, n);

	// copy to host c from GPU dev_c
	cudaMemcpy(b, dev_b, n * sizeof(float), cudaMemcpyDeviceToHost);

    return(b_bin);
}


static ERL_NIF_TERM
activate_softmax(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary  a_bin;
    ERL_NIF_TERM  b_bin;
    int r1, c1, n, i, j, k;
    float *a,*b;
    float max,sum;

    if (!enif_get_int(env, argv[0], &r1)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &c1)) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[2], &a_bin )) return enif_make_badarg(env);
    n = r1*c1;
    a = (float *) a_bin.data;
    b = (float *) enif_make_new_binary(env, n * sizeof(float), &b_bin);

    //calculate softmax
    for(i=0;i<r1;i++){
        for(j=0;j<c1;j++){
            max = 0.0;
            for(k=0;k<c1;k++){
                if(a[IDX2C(i,k,r1)] > max)
                    max = a[IDX2C(i,k,r1)];
            }
            sum = 0.0;
            for(k=0;k<c1;k++){
                sum = sum + exp(a[IDX2C(i,k,r1)] - max);
            }
            b[IDX2C(i,j,r1)] = exp(a[IDX2C(i,j,r1)] - max) / sum;
        }
    }


    return(b_bin);
}



__global__ void differ_sigmoid_kernel(float *a, float *b, float *c, int n)
{
	int tid = threadIdx.x + blockIdx.x * blockDim.x;
	while (tid < n)
	{   
        
		c[tid] = a[tid] * ((1 - SIGMOID(b[tid])) * SIGMOID(b[tid]));
		tid += blockDim.x * gridDim.x;
	}
}

static ERL_NIF_TERM
differ_sigmoid(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary  a_bin, b_bin;
    ERL_NIF_TERM  c_bin;
    int r1, c1, n;
    float *a,*b,*c;
    float *dev_a, *dev_b, *dev_c;

    if (!enif_get_int(env, argv[0], &r1)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &c1)) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[2], &a_bin )) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[3], &b_bin)) return enif_make_badarg(env);
    n = r1*c1;
    a = (float *) a_bin.data;
    b = (float *) b_bin.data;
    c = (float *) enif_make_new_binary(env, n * sizeof(float), &c_bin);

    	// Allocate for GPU
	cudaMalloc((void**)&dev_a, n * sizeof(float));
	cudaMalloc((void**)&dev_b, n * sizeof(float));
	cudaMalloc((void**)&dev_c, n * sizeof(float));


    // copy from host a,b to GPU dev_a, dev_b
	cudaMemcpy(dev_a, a, n * sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(dev_b, b, n * sizeof(float), cudaMemcpyHostToDevice);

	differ_sigmoid_kernel << <128, 128 >> >(dev_a, dev_b, dev_c, n);

	// copy to host c from GPU dev_c
	cudaMemcpy(c, dev_c, n * sizeof(float), cudaMemcpyDeviceToHost);

    // free 
    cudaFree(dev_a);
	cudaFree(dev_b);
	cudaFree(dev_c);

    return(c_bin);
}


__global__ void differ_tanh_kernel(float *a, float *b, float *c, int n)
{
	int tid = threadIdx.x + blockIdx.x * blockDim.x;
	while (tid < n)
	{   
        c[tid] = a[tid] * (1/(cosh(b[tid]) * cosh(b[tid])));
		tid += blockDim.x * gridDim.x;
	}
}

static ERL_NIF_TERM
differ_tanh(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary  a_bin, b_bin;
    ERL_NIF_TERM  c_bin;
    int r1, c1, n;
    float *a,*b,*c;
    float *dev_a, *dev_b, *dev_c;

    if (!enif_get_int(env, argv[0], &r1)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &c1)) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[2], &a_bin )) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[3], &b_bin)) return enif_make_badarg(env);
    n = r1*c1;
    a = (float *) a_bin.data;
    b = (float *) b_bin.data;
    c = (float *) enif_make_new_binary(env, n * sizeof(float), &c_bin);

    	// Allocate for GPU
	cudaMalloc((void**)&dev_a, n * sizeof(float));
	cudaMalloc((void**)&dev_b, n * sizeof(float));
	cudaMalloc((void**)&dev_c, n * sizeof(float));


    // copy from host a,b to GPU dev_a, dev_b
	cudaMemcpy(dev_a, a, n * sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(dev_b, b, n * sizeof(float), cudaMemcpyHostToDevice);

	differ_tanh_kernel << <128, 128 >> >(dev_a, dev_b, dev_c, n);

	// copy to host c from GPU dev_c
	cudaMemcpy(c, dev_c, n * sizeof(float), cudaMemcpyDeviceToHost);

    // free 
    cudaFree(dev_a);
	cudaFree(dev_b);
	cudaFree(dev_c);

    return(c_bin);
}



__global__ void differ_relu_kernel(float *a, float *b, float *c, int n)
{
	int tid = threadIdx.x + blockIdx.x * blockDim.x;
	while (tid < n)
	{   
        if(b[tid] >= 0)
		    c[tid] = a[tid];
        else 
            c[tid] = 0.0;
		tid += blockDim.x * gridDim.x;
	}
}

static ERL_NIF_TERM
differ_relu(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary  a_bin, b_bin;
    ERL_NIF_TERM  c_bin;
    int r1, c1, n;
    float *a,*b,*c;
    float *dev_a, *dev_b, *dev_c;

    if (!enif_get_int(env, argv[0], &r1)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &c1)) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[2], &a_bin )) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[3], &b_bin)) return enif_make_badarg(env);
    n = r1*c1;
    a = (float *) a_bin.data;
    b = (float *) b_bin.data;
    c = (float *) enif_make_new_binary(env, n * sizeof(float), &c_bin);

    	// Allocate for GPU
	cudaMalloc((void**)&dev_a, n * sizeof(float));
	cudaMalloc((void**)&dev_b, n * sizeof(float));
	cudaMalloc((void**)&dev_c, n * sizeof(float));


    // copy from host a,b to GPU dev_a, dev_b
	cudaMemcpy(dev_a, a, n * sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(dev_b, b, n * sizeof(float), cudaMemcpyHostToDevice);

	differ_relu_kernel << <128, 128 >> >(dev_a, dev_b, dev_c, n);

	// copy to host c from GPU dev_c
	cudaMemcpy(c, dev_c, n * sizeof(float), cudaMemcpyDeviceToHost);

    // free 
    cudaFree(dev_a);
	cudaFree(dev_b);
	cudaFree(dev_c);

    return(c_bin);
}


__global__ void smult_kernel(float d, float *a, float *b, int n)
{
	int tid = threadIdx.x + blockIdx.x * blockDim.x;
	while (tid < n)
	{
		b[tid] = d * a[tid];
		tid += blockDim.x * gridDim.x;
	}
}


static ERL_NIF_TERM
smult1(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary  a_bin;
    ERL_NIF_TERM  b_bin;
    int r1, c1, n;
    float *a,*b;
    float *dev_a, *dev_b;
    double s;


    if (!enif_get_double(env, argv[0], &s)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &r1)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[2], &c1)) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[3], &a_bin )) return enif_make_badarg(env);
    n = r1*c1;
    a = (float *) a_bin.data;
    b = (float *) enif_make_new_binary(env, n * sizeof(float), &b_bin);

    	// Allocate for GPU
	cudaMalloc((void**)&dev_a, n * sizeof(float));
	cudaMalloc((void**)&dev_b, n * sizeof(float));


    // copy from host a,b to GPU dev_a, dev_b
	cudaMemcpy(dev_a, a, n * sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(dev_b, b, n * sizeof(float), cudaMemcpyHostToDevice);

	smult_kernel << <128, 128 >> >((float)s,dev_a, dev_b, n);

	// copy to host c from GPU dev_c
	cudaMemcpy(b, dev_b, n * sizeof(float), cudaMemcpyDeviceToHost);

    // free 
    cudaFree(dev_a);
	cudaFree(dev_b);

    return(b_bin);
}


static ERL_NIF_TERM
trace1(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary  a_bin;
    ERL_NIF_TERM  result;
    int r1, c1, i, j;
    float *a;
    float trace;

    if (!enif_get_int(env, argv[0], &r1)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &c1)) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[2], &a_bin )) return enif_make_badarg(env);
    a = (float *) a_bin.data;
    
    trace = 0.0;
    for(i=0;i<r1;i++){
        for(j=0;j<c1;j++){
            if(i==j)
                trace = trace + a[IDX2C(i,j,r1)];
        }
    }

    result = enif_make_double(env,trace);

    return(result);
}


static ERL_NIF_TERM
mean_square(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary  a_bin,b_bin;
    ERL_NIF_TERM  c_bin;
    int r1, c1, i, j;
    float *a, *b, *c;
    float d,s;


    if (!enif_get_int(env, argv[0], &r1)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &c1)) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[2], &a_bin )) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[3], &b_bin )) return enif_make_badarg(env);

    a = (float *) a_bin.data;
    b = (float *) b_bin.data;
    c = (float *) enif_make_new_binary(env, r1 * sizeof(float), &c_bin);

    // Set matrix After kernel
    for(i=0;i<r1;i++){
        s = 0.0;
        for (j=0;j<c1;j++){
            //printf("%f %f\n",  a[IDX2C(i,j,r1)],  b[IDX2C(i,j,r1)]);
            d = a[IDX2C(i,j,r1)] -  b[IDX2C(i,j,r1)];
            //printf("%f", d);
            s = s + d*d;            
        }
        c[IDX2C(i,0,r1)] = s / 2;
    } 


    return(c_bin);
}

static ERL_NIF_TERM
cross_entropy(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary  a_bin,b_bin;
    ERL_NIF_TERM  c_bin;
    int r1, c1, i, j;
    float *a, *b, *c;
    float d,s,delta;


    if (!enif_get_int(env, argv[0], &r1)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &c1)) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[2], &a_bin )) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[3], &b_bin )) return enif_make_badarg(env);

    a = (float *) a_bin.data;
    b = (float *) b_bin.data;
    c = (float *) enif_make_new_binary(env, r1 * sizeof(float), &c_bin);

    
    delta = 1e-7;
    for(i=0;i<r1;i++){
        s = 0.0;
        for (j=0;j<c1;j++){
            d = a[IDX2C(i,j,r1)];
            s = s + b[IDX2C(i,j,r1)] * log(d+delta);             
        }
        c[IDX2C(i,0,r1)] = s;
    }

    return(c_bin);
}





static ERL_NIF_TERM
elt1(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary  a_bin;
    ERL_NIF_TERM  result;
    int r1, c1, i, j;
    float *a;

    if (!enif_get_int(env, argv[0], &r1)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &c1)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[2], &i)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[3], &j)) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[4], &a_bin )) return enif_make_badarg(env);
    a = (float *) a_bin.data;
    
    result = enif_make_double(env,(double)a[IDX2C(i,j,r1)]);

    return(result);
}

static ERL_NIF_TERM
minus1(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary  a_bin;
    ERL_NIF_TERM  b_bin;
    int r1, c1, n, i, j, x, y;
    float *a,*b;
    double val;

    if (!enif_get_int(env, argv[0], &r1)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &c1)) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[2], &a_bin )) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[3], &x)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[4], &y)) return enif_make_badarg(env);
    if (!enif_get_double(env, argv[5], &val)) return enif_make_badarg(env);


    n = r1*c1;
    a = (float *) a_bin.data;
    b = (float *) enif_make_new_binary(env, n * sizeof(float), &b_bin);

    for(i=0;i<r1;i++){
        for(j=0;j<c1;j++){
            if(i==x && j==y)
                b[IDX2C(i,j,r1)] = a[IDX2C(i,j,r1)] - (float)val;
            else 
                b[IDX2C(i,j,r1)] = a[IDX2C(i,j,r1)];
        }
    }


    return(b_bin);
}

static ERL_NIF_TERM
average1(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary  a_bin;
    ERL_NIF_TERM  b_bin;
    int r1, c1, i, j;
    float *a,*b;
    float sum;

    if (!enif_get_int(env, argv[0], &r1)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &c1)) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[2], &a_bin )) return enif_make_badarg(env);

    a = (float *) a_bin.data;
    b = (float *) enif_make_new_binary(env, c1 * sizeof(float), &b_bin);

    for(j=0;j<c1;j++){
        sum = 0.0;
        for(i=0;i<r1;i++){
            sum = sum + a[IDX2C(i,j,r1)];
        }
        b[j] = sum / r1;
    }


    return(b_bin);
}


static ERL_NIF_TERM
sum1(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary  a_bin;
    ERL_NIF_TERM  result;
    int r1, c1, i, j;
    float *a;
    float sum;

    if (!enif_get_int(env, argv[0], &r1)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &c1)) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[2], &a_bin )) return enif_make_badarg(env);
    a = (float *) a_bin.data;
    
    sum = 0.0;
    for(i=0;i<r1;i++){
        for(j=0;j<c1;j++){
            sum = sum + a[IDX2C(i,j,r1)];
        }
    }

    result = enif_make_double(env,sum);

    return(result);
}

static ERL_NIF_TERM
to_list1(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary  a_bin;
    ERL_NIF_TERM  head,list;
    int r1, c1, i, j;
    float *a;


    if (!enif_get_int(env, argv[0], &r1)) return enif_make_badarg(env);
    if (!enif_get_int(env, argv[1], &c1)) return enif_make_badarg(env);
    if (!enif_inspect_binary(env, argv[2], &a_bin )) return enif_make_badarg(env);
    a = (float *) a_bin.data;

    
    list = enif_make_list(env, 0);
    for(i=r1-1;i>=0;i--){
        for(j=c1-1;j>=0;j--){
            head = enif_make_double(env,(double)a[IDX2C(i,j,r1)]);
            list = enif_make_list_cell(env,head,list);
        }
    }

    return(list);
}


// define the array of ErlNifFunc
static ErlNifFunc nif_funcs[] = {
  // {erl_function_name, erl_function_arity, c_function}
  {"print1", 3, print1},
  {"mult1", 6, mult},
  {"new1", 2, new1},
  {"new2", 3, new2},
  {"rand1", 1, rand1},
  {"add1", 4, add1},
  {"sub1", 4, sub1},
  {"emult1", 4, emult1},
  {"transpose1", 3, transpose1},
  {"ident1", 1, ident1},
  {"activate_sigmoid", 3 ,activate_sigmoid},
  {"activate_tanh", 3 , activate_tanh},
  {"activate_relu", 3, activate_relu},
  {"activate_softmax", 3, activate_softmax},
  {"differ_sigmoid", 4, differ_sigmoid},
  {"differ_tanh", 4, differ_tanh},
  {"differ_relu", 4, differ_relu},
  {"smult1", 4, smult1},
  {"trace1", 3, trace1},
  {"mean_square", 4, mean_square},
  {"cross_entropy", 4, cross_entropy},
  {"elt1", 5, elt1},
  {"minus1", 6, minus1},
  {"average1", 3, average1},
  {"sum1", 3, sum1},
  {"to_list1", 3, to_list1}
};

ERL_NIF_INIT(Elixir.Cumatrix, nif_funcs, NULL, NULL, NULL, NULL)

