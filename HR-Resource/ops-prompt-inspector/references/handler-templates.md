# API Handler Templates

## Success/Failure Handler Types

### 1. Toast Messages

```tsx
// Using react-hot-toast
import toast from 'react-hot-toast';

// Success
toast.success('${message}');

// Error
toast.error('${message}');
```

```tsx
// Using sonner
import { toast } from 'sonner';

// Success
toast.success('${message}');

// Error
toast.error('${message}');
```

```tsx
// Using react-toastify
import { toast } from 'react-toastify';

// Success
toast.success('${message}');

// Error
toast.error('${message}');
```

### 2. Alert/Popup Dialogs

```tsx
// Native browser alert
alert('${message}');

// Using shadcn/ui AlertDialog
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";

<AlertDialog open={isOpen} onOpenChange={setIsOpen}>
  <AlertDialogContent>
    <AlertDialogHeader>
      <AlertDialogTitle>${title}</AlertDialogTitle>
      <AlertDialogDescription>${message}</AlertDialogDescription>
    </AlertDialogHeader>
    <AlertDialogFooter>
      <AlertDialogAction onClick={() => setIsOpen(false)}>
        확인
      </AlertDialogAction>
    </AlertDialogFooter>
  </AlertDialogContent>
</AlertDialog>
```

### 3. Page Navigation

```tsx
// Using Next.js App Router
import { useRouter } from 'next/navigation';

const router = useRouter();

// Success redirect
router.push('${successPath}');

// With replace (no back button)
router.replace('${successPath}');
```

```tsx
// Using Next.js Pages Router
import { useRouter } from 'next/router';

const router = useRouter();
router.push('${successPath}');
```

### 4. State Update

```tsx
// Update local state
setData(response.data);
setLoading(false);
setError(null);

// With React Query
queryClient.invalidateQueries({ queryKey: ['${queryKey}'] });
```

---

## Combined Handler Patterns

### Pattern A: Toast + State Update

```tsx
const handleSuccess = (data: ResponseType) => {
  toast.success('${successMessage}');
  setData(data);
  setLoading(false);
};

const handleError = (error: Error) => {
  toast.error('${errorMessage}');
  setError(error.message);
  setLoading(false);
};
```

### Pattern B: Toast + Navigation

```tsx
const handleSuccess = () => {
  toast.success('${successMessage}');
  router.push('${successPath}');
};

const handleError = (error: Error) => {
  toast.error(error.message || '${errorMessage}');
};
```

### Pattern C: Popup Dialog + Navigation

```tsx
const handleSuccess = () => {
  setDialogConfig({
    open: true,
    title: '${successTitle}',
    message: '${successMessage}',
    onConfirm: () => router.push('${successPath}'),
  });
};

const handleError = (error: Error) => {
  setDialogConfig({
    open: true,
    title: '${errorTitle}',
    message: error.message || '${errorMessage}',
    onConfirm: () => setDialogConfig({ open: false }),
  });
};
```

---

## Trigger Patterns

### onLoad (페이지 로딩 시)

```tsx
// Using useEffect
useEffect(() => {
  fetchData();
}, []);

// Using React Query
const { data, isLoading, error } = useQuery({
  queryKey: ['${queryKey}'],
  queryFn: () => fetch('${apiPath}').then(res => res.json()),
});

// Using SWR
const { data, error, isLoading } = useSWR('${apiPath}', fetcher);
```

### onClick (클릭 시)

```tsx
<button onClick={async () => {
  try {
    setLoading(true);
    const response = await axios.${method}('${apiPath}', ${hasBody ? 'payload' : ''});
    handleSuccess(response.data);
  } catch (error) {
    handleError(error);
  }
}}>
  ${buttonText}
</button>
```

### onSubmit (폼 제출 시)

```tsx
const handleSubmit = async (e: React.FormEvent) => {
  e.preventDefault();
  try {
    setLoading(true);
    const response = await axios.${method}('${apiPath}', formData);
    handleSuccess(response.data);
  } catch (error) {
    handleError(error);
  }
};

<form onSubmit={handleSubmit}>
  {/* form fields */}
  <button type="submit" disabled={loading}>
    {loading ? '처리 중...' : '${submitText}'}
  </button>
</form>
```

### onBlur (포커스 해제 시)

```tsx
<input
  onBlur={async (e) => {
    const value = e.target.value;
    if (value !== previousValue) {
      try {
        await axios.${method}('${apiPath}', { value });
        handleSuccess();
      } catch (error) {
        handleError(error);
      }
    }
  }}
/>
```

### onChange with Debounce (입력 변경 시)

```tsx
import { useDebouncedCallback } from 'use-debounce';

const debouncedSave = useDebouncedCallback(async (value: string) => {
  try {
    await axios.${method}('${apiPath}', { value });
    handleSuccess();
  } catch (error) {
    handleError(error);
  }
}, 500);

<input onChange={(e) => debouncedSave(e.target.value)} />
```
